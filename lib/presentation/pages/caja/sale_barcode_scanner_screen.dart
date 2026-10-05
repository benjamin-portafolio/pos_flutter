import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../application/commands/ventas/agregar_producto_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/articulos/codigo_barras.dart';
import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../../../domain/ventas/sale_draft_item.dart';
import '../articulos/sale_quantity_dialog.dart';
import 'barcode/barcode_product_selection_dialog.dart';
import 'barcode/barcode_read_gate.dart';
import 'models/sale_draft_display.dart';

/// Escaneo continuo sobre el mismo borrador persistido que observa Caja.
class SaleBarcodeScannerScreen extends StatefulWidget {
  const SaleBarcodeScannerScreen({
    this.productoRepository,
    this.saleDraftRepository,
    this.ventaBorradorCommandService,
    this.readGate,
    super.key,
  });

  final ProductoRepository? productoRepository;
  final SaleDraftRepository? saleDraftRepository;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final BarcodeReadGate? readGate;

  @override
  State<SaleBarcodeScannerScreen> createState() =>
      _SaleBarcodeScannerScreenState();
}

class _SaleBarcodeScannerScreenState extends State<SaleBarcodeScannerScreen>
    with WidgetsBindingObserver {
  late final _products =
      widget.productoRepository ?? getIt<ProductoRepository>();
  late final _commands =
      widget.ventaBorradorCommandService ??
      getIt<VentaBorradorCommandService>();
  late final _draft =
      (widget.saleDraftRepository ?? getIt<SaleDraftRepository>())
          .watchCurrentDraft();
  final _clock = Stopwatch()..start();
  late final _gate =
      widget.readGate ?? BarcodeReadGate(clock: () => _clock.elapsed);
  // Misma cámara/permisos del editor; observaciones continuas del prototipo.
  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 200,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.itf14,
    ],
  );
  Future<void> _cameraOperation = Future.value();
  Future<void> _readOperation = Future.value();
  bool _appActive = true;
  bool _routeActive = false;
  bool _dialogOpen = false;
  bool _busy = false;
  bool _closing = false;
  bool _disposed = false;
  bool _ambiguous = false;
  int _readGeneration = 0;
  String _message = 'Enfoca una etiqueta dentro del marco.';
  String? _cameraError;

  bool get _wantsCamera =>
      !_disposed &&
      !_closing &&
      _appActive &&
      _routeActive &&
      !_dialogOpen &&
      _cameraError == null;

  bool get _canContinueRead =>
      mounted &&
      !_closing &&
      !_disposed &&
      _appActive &&
      _cameraError == null &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller.addListener(_cameraChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeActive == active) return;
    _routeActive = active;
    // Una ruta externa invalida consultas pendientes; nuestros selectores
    // forman parte de la misma lectura y pueden continuar al confirmarse.
    if (!active && !_dialogOpen) _readGeneration++;
    _gate.setCameraActive(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCamera());
  }

  void _cameraChanged() =>
      _gate.setCameraActive(_wantsCamera && _controller.value.isRunning);

  /// Serializa start/stop/dispose también durante la solicitud de permiso.
  void _updateCamera() {
    _cameraOperation = _cameraOperation.then((_) async {
      try {
        if (!_wantsCamera) {
          _gate.setCameraActive(false);
          await _controller.stop();
          return;
        }
        await _controller.start();
        if (!_wantsCamera) await _controller.stop();
        _cameraChanged();
      } catch (error) {
        _gate.setCameraActive(false);
        if (mounted && !_closing) {
          setState(() => _cameraError = _cameraMessage(error));
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Un diálogo requiere confirmación explícita al volver. La pausa invalida
    // consultas pendientes, sin descartar esa intención posterior del usuario.
    if (_appActive && state != AppLifecycleState.resumed && !_dialogOpen) {
      _readGeneration++;
    }
    _appActive = state == AppLifecycleState.resumed;
    _gate.setCameraActive(false);
    if (_controller.value.hasCameraPermission) _updateCamera();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_wantsCamera || !_controller.value.isRunning || !_canContinueRead) {
      return;
    }
    final codes = <String>{};
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final code = CodigoBarras.fromInput(raw).value;
        if (code != null) codes.add(code);
      } on ArgumentError {
        codes.add('\u0000$raw');
      }
    }
    // Seguir observando presencia mientras consulta/guardado ocupan la UI.
    final accepted = _gate.observe(codes, admissionEnabled: !_busy);
    if (codes.length > 1) {
      if (!_ambiguous && !_busy) {
        setState(() => _message = 'Enfoca un solo código dentro del marco.');
      }
      _ambiguous = !_busy;
      return;
    }
    _ambiguous = false;
    if (accepted == null) return;
    if (accepted.startsWith('\u0000')) {
      setState(() => _message = 'El código debe tener hasta 32 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Buscando artículo…';
    });
    _readOperation = _read(accepted, _readGeneration);
  }

  Future<T?> _showReaderDialog<T>(WidgetBuilder builder) async {
    _dialogOpen = true;
    _gate.setCameraActive(false);
    _updateCamera();
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      _dialogOpen = false;
      _updateCamera();
    }
  }

  bool _canFinishRead(int generation) {
    if (_canContinueRead && generation == _readGeneration) return true;
    _setMessage(
      'Lectura interrumpida. Retira la etiqueta para volver a leerla.',
    );
    return false;
  }

  Future<void> _read(String code, int generation) async {
    try {
      final candidates = await _products.buscarVariantesPorCodigoBarras(code);
      if (!_canFinishRead(generation)) return;
      if (candidates.isEmpty) {
        _setMessage('No se encontró un artículo con este código.');
        return;
      }
      final candidate = candidates.length == 1
          ? candidates.single
          : await _showReaderDialog<VariantePorCodigoBarras>(
              (_) => BarcodeProductSelectionDialog(candidates: candidates),
            );
      if (!_canFinishRead(generation)) return;
      if (candidate == null) {
        _setMessage(
          'Selección cancelada. Retira la etiqueta para volver a leerla.',
        );
        return;
      }
      String? quantity;
      final unit = candidate.unidadVenta;
      if (candidate.saleConfiguration is MeasuredSaleConfiguration) {
        if (unit == null || !unit.activa) {
          _setMessage(
            'La unidad de venta no está disponible. Vuelve a seleccionar el artículo.',
          );
          return;
        }
        quantity = await _showReaderDialog<String>(
          (_) => SaleQuantityDialog(
            productName: [
              candidate.nombreProducto,
              if (candidate.nombreVariante != null) candidate.nombreVariante!,
            ].join(' · '),
            unit: unit,
          ),
        );
        if (!_canFinishRead(generation)) return;
        if (quantity == null) {
          _setMessage(
            'Cantidad cancelada. Retira la etiqueta para volver a leerla.',
          );
          return;
        }
      }
      _setMessage('Guardando artículo…');
      await _commands.agregar(
        AgregarProductoBorradorCommand(
          variantId: candidate.varianteId,
          measuredQuantity: quantity,
          expectedUnitId: unit?.id,
        ),
      );
      _setMessage('Artículo agregado. Retira la etiqueta para repetir.');
    } on FormatException catch (error) {
      _setMessage(error.message);
    } on StateError catch (error) {
      _setMessage(error.message.toString());
    } catch (_) {
      _setMessage(
        'No se pudo agregar el artículo. Retira la etiqueta antes de reintentar.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMessage(String message) {
    if (mounted && !_closing) setState(() => _message = message);
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    _gate.setCameraActive(false);
    _updateCamera();
    // No hay rollback al salir: termina cualquier operación ya iniciada.
    await _readOperation;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _disposed = true;
    _gate.setCameraActive(false);
    _clock.stop();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_cameraChanged);
    unawaited(
      _cameraOperation.whenComplete(_controller.dispose).catchError((
        Object error,
      ) {
        debugPrint('No se pudo liberar la cámara de Caja: $error');
      }),
    );
    super.dispose();
  }

  String _cameraMessage(Object error) => switch (error) {
    MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    ) =>
      'Permite el acceso a la cámara en los ajustes y vuelve a abrir el lector. Puedes usar el buscador de Caja.',
    MobileScannerException(errorCode: MobileScannerErrorCode.unsupported) =>
      'No hay una cámara disponible. Puedes usar el buscador de Caja.',
    _ =>
      'No se pudo iniciar la cámara. Vuelve a abrir el lector o usa el buscador de Caja.',
  };

  Widget _camera() => LayoutBuilder(
    builder: (context, constraints) {
      final window = Rect.fromCenter(
        center: constraints.biggest.center(Offset.zero),
        width: constraints.maxWidth * .85,
        height: constraints.maxHeight * .35,
      );
      return ColoredBox(
        color: const Color(0xFF101010),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraError case final error?)
              _CameraNotice(message: error)
            else
              MobileScanner(
                controller: _controller,
                useAppLifecycleState: false,
                scanWindow: window,
                onDetect: _onDetect,
                onDetectError: (_, _) {
                  if (!mounted || _closing || _disposed) return;
                  _gate.setCameraActive(false);
                  setState(
                    () => _cameraError =
                        'Se interrumpió la cámara. Vuelve a abrir el lector o usa el buscador de Caja.',
                  );
                  _updateCamera();
                },
                errorBuilder: (_, error) =>
                    _CameraNotice(message: _cameraMessage(error)),
              ),
            if (_cameraError == null && _controller.value.error == null)
              Positioned.fromRect(
                rect: window,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                      child: Divider(color: Colors.redAccent, thickness: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _readerMessage() => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        _closing ? 'Esperando la operación para cerrar…' : _message,
        key: const Key('sale_barcode_status'),
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _draftCards(
    AsyncSnapshot<SaleDraft?> snapshot, {
    bool compact = false,
  }) {
    if (snapshot.hasError) {
      return const Center(child: Text('No se pudo cargar la venta.'));
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    return _SaleCards(items: snapshot.data?.items ?? [], shrinkWrap: compact);
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    // Todo regreso pasa por _close, incluso antes del próximo rebuild tras
    // admitir una lectura. Navigator.pop se ejecuta al resolver la operación.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        _closing = true;
        _gate.setCameraActive(false);
        _updateCamera();
      } else {
        unawaited(_close());
      }
    },
    child: Scaffold(
      key: const Key('sale_barcode_scanner_screen'),
      backgroundColor: const Color(0xFFE6E6E6),
      appBar: AppBar(
        title: const Text('Escanear artículos'),
        leading: IconButton(
          key: const Key('close_sale_barcode_scanner'),
          onPressed: _closing ? null : _close,
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<SaleDraft?>(
          stream: _draft,
          builder: (context, snapshot) {
            final sale = snapshot.hasError ? null : snapshot.data;
            final count = sale?.articleCount ?? 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Con poco alto y texto ampliado, desplazar el área de
                      // lectura mantiene cámara, aviso y tarjetas utilizables.
                      // El total y el regreso permanecen siempre en el pie.
                      final scale =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      final minimumHeight = 280 + 80 * scale;
                      if (constraints.maxHeight < minimumHeight) {
                        return SingleChildScrollView(
                          key: const Key('sale_barcode_compact_scroll'),
                          child: Column(
                            children: [
                              SizedBox(height: 140, child: _camera()),
                              _readerMessage(),
                              _draftCards(snapshot, compact: true),
                            ],
                          ),
                        );
                      }
                      return Column(
                        children: [
                          Expanded(flex: 3, child: _camera()),
                          _readerMessage(),
                          Expanded(flex: 4, child: _draftCards(snapshot)),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Total: ${SaleDraftDisplay.money(sale?.totalMinor ?? 0)}',
                        key: const Key('sale_barcode_total'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: const Key('sale_barcode_go_to_caja'),
                        onPressed:
                            sale == null ||
                                sale.items.isEmpty ||
                                _busy ||
                                _closing
                            ? null
                            : _close,
                        child: Text(
                          'Ir a caja ($count ${count == 1 ? 'artículo' : 'artículos'})',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _CameraNotice extends StatelessWidget {
  const _CameraNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        key: const Key('sale_barcode_camera_error'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white),
      ),
    ),
  );
}

class _SaleCards extends StatelessWidget {
  const _SaleCards({required this.items, this.shrinkWrap = false});
  final List<SaleDraftItem> items;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('La venta está vacía.'));
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (260 * scale)).floor().clamp(
          1,
          3,
        );
        return ListView.builder(
          key: const Key('sale_barcode_cards'),
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(12),
          itemCount: (items.length / columns).ceil(),
          itemBuilder: (_, row) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * columns + column < items.length
                        ? _SaleCard(item: items[row * columns + column])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.item});
  final SaleDraftItem item;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('sale_barcode_line_${item.id}'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.productName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (item.variantName != null) Text(item.variantName!),
          const SizedBox(height: 4),
          Text('Precio: ${SaleDraftDisplay.price(item)}'),
          Text('Cantidad: ${SaleDraftDisplay.quantity(item)}'),
          Text(SaleDraftDisplay.money(item.totalMinor)),
        ],
      ),
    ),
  );
}
