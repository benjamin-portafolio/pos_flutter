import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';

import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../articulos/sale_quantity_dialog.dart';
import 'barcode_product_selection_dialog.dart';
import 'physical_barcode_finish_dialog.dart';
import 'physical_barcode_read_admission.dart';
import 'physical_barcode_reader_controller.dart';
import 'sale_barcode_read_coordinator.dart';
import 'sale_barcode_read_outcome.dart';
import 'sale_barcode_read_result.dart';

/// Campo HID de Caja. La cola y sus comandos pertenecen al controlador;
/// este widget coordina únicamente captura, foco, diálogos y ciclo de vida.
class PhysicalBarcodeReader extends StatefulWidget {
  const PhysicalBarcodeReader({
    required this.coordinator,
    this.interactionEnabled = true,
    super.key,
  });

  final SaleBarcodeReadCoordinator coordinator;
  final bool interactionEnabled;

  @override
  PhysicalBarcodeReaderState createState() => PhysicalBarcodeReaderState();
}

class PhysicalBarcodeReaderState extends State<PhysicalBarcodeReader>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Lector físico');
  PhysicalBarcodeReaderController? _session;
  SaleBarcodeReadResult? _shownResult;
  Future<void>? _finishOperation;
  Completer<void>? _readerDialogClosed;
  int _ownDialogDepth = 0;
  int _interruptionGeneration = 0;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _windowFocused = true;
  bool _closing = false;
  bool _requiresExplicitResume = false;
  String? _notice;

  bool get isEnabled => _session != null;
  int get interruptionGeneration => _interruptionGeneration;
  bool get _available => _routeVisible && _appActive && _windowFocused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    if (!_routeVisible && _ownDialogDepth == 0 && _session != null) {
      // Rutas ajenas requieren reanudación explícita al regresar.
      _interruptionGeneration++;
      _requiresExplicitResume = true;
      pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) _interrupt();
    if (mounted) setState(() {});
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _windowFocused = event.state == ViewFocusState.focused;
    if (!_windowFocused) _interrupt();
    if (mounted) setState(() {});
  }

  void _interrupt() {
    _interruptionGeneration++;
    _requiresExplicitResume = true;
    pause();
  }

  void pause() {
    _text.clear();
    _session?.pause();
  }

  void enableReader({int? restoringGeneration}) {
    if (!mounted || _closing || _session != null) return;
    final session = PhysicalBarcodeReaderController(
      coordinator: widget.coordinator,
      selectProduct: (candidates) => _showReaderDialog<VariantePorCodigoBarras>(
        (_) => BarcodeProductSelectionDialog(candidates: candidates),
      ),
      requestQuantity: (candidate) => _showReaderDialog<String>(
        (_) => SaleQuantityDialog(
          productName: [
            candidate.nombreProducto,
            if (candidate.nombreVariante != null) candidate.nombreVariante!,
          ].join(' · '),
          unit: candidate.unidadVenta!,
        ),
      ),
    );
    _session = session;
    _shownResult = null;
    _notice = null;
    _requiresExplicitResume =
        !_appActive ||
        !_windowFocused ||
        (restoringGeneration != null &&
            restoringGeneration != _interruptionGeneration);
    session.addListener(_changed);
    session.activate();
    if (!_available ||
        (restoringGeneration != null &&
            restoringGeneration != _interruptionGeneration)) {
      session.pause();
    }
    if (!_requiresExplicitResume) {
      _requestFocus(session);
    }
    setState(() {});
  }

  void _requestFocus(PhysicalBarcodeReaderController session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_session, session) && !_closing && _available) {
        _focus.requestFocus();
      }
    });
  }

  void _resume() {
    if (!_available || _closing) return;
    _requiresExplicitResume = false;
    _text.clear();
    _session?.resume();
    _focus.requestFocus();
  }

  void _focusChanged() {
    final session = _session;
    if (session == null || _closing || _ownDialogDepth > 0) return;
    if (!_focus.hasFocus) {
      pause();
    } else if (_available && !_requiresExplicitResume) {
      session.resume();
    }
    if (mounted) setState(() {});
  }

  void _submit(String _) {
    // onSubmitted es la única frontera. Copiar antes de limpiar evita que un
    // Enter repetido vuelva a enviar el texto entregado por un callback antiguo.
    final input = _text.text;
    _text.clear();
    final session = _session;
    if (session == null ||
        !widget.interactionEnabled ||
        !_available ||
        !_focus.hasFocus ||
        _closing) {
      return;
    }
    final admission = session.submit(input);
    if (admission == PhysicalBarcodeReadAdmission.invalid) {
      setState(() => _notice = 'El código debe tener hasta 32 dígitos.');
    }
  }

  void _changed() {
    final session = _session;
    if (!mounted || session == null) return;
    final result = session.lastResult;
    if (result != null && !identical(result, _shownResult)) {
      _shownResult = result;
      _notice = switch (result.outcome) {
        SaleBarcodeReadOutcome.added =>
          'Agregado: ${result.candidate!.nombreProducto} · '
              '${result.measuredQuantity ?? "1"} '
              '${result.candidate!.unidadVenta?.simbolo ?? "unidad"}',
        SaleBarcodeReadOutcome.notFound =>
          'No se encontró un artículo con este código.',
        SaleBarcodeReadOutcome.selectionCancelled => 'Selección cancelada.',
        SaleBarcodeReadOutcome.quantityCancelled => 'Cantidad cancelada.',
        SaleBarcodeReadOutcome.unitUnavailable =>
          'La unidad de venta no está disponible.',
        SaleBarcodeReadOutcome.interrupted => 'Lectura interrumpida.',
      };
    }
    if (session.isPaused) _text.clear();
    setState(() {});
  }

  Future<T?> _showReaderDialog<T>(WidgetBuilder builder) async {
    final session = _session;
    final generation = _interruptionGeneration;
    if (!mounted || session == null || session.isFinished) return null;
    _ownDialogDepth++;
    final closed = Completer<void>();
    _readerDialogClosed = closed;
    _text.clear();
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      _ownDialogDepth--;
      _readerDialogClosed = null;
      closed.complete();
      if (mounted && identical(_session, session) && !session.isFinished) {
        // El controlador suspende admisión durante el diálogo. La pérdida de
        // foco de ese diálogo no debe convertirse en una pausa externa.
        if (_appActive &&
            _windowFocused &&
            !_closing &&
            session.error == null &&
            generation == _interruptionGeneration) {
          _requestFocus(session);
        }
      }
    }
  }

  /// Se espera `done` antes de permitir cualquier cambio de borrador/contexto.
  Future<void> finish() {
    if (_session == null) return Future<void>.value();
    return _finishOperation ??= _finishSession();
  }

  Future<void> _finishSession() async {
    final session = _session;
    if (session == null) return;
    setState(() => _closing = true);
    _text.clear();
    _focus.unfocus();
    final done = session.finish();
    // Un selector ya visible se resuelve primero. Cubrirlo con el diálogo de
    // drenaje impediría cancelar/confirmar la lectura que finish está esperando.
    await _readerDialogClosed?.future;
    if (!session.isFinished && mounted) {
      _ownDialogDepth++;
      final navigator = Navigator.of(context);
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhysicalBarcodeFinishDialog(
          controller: session,
          onResume: () {
            if (_appActive && _windowFocused) session.resume();
          },
        ),
      );
      final dialogClosed = navigator.push(route);
      await done;
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      await dialogClosed;
      _ownDialogDepth--;
    } else {
      await done;
    }
    if (mounted && session.error != null) {
      // Si falló la última intención, finish ya terminó sin cola. Mantener el
      // error visible antes de abrir la siguiente operación, incluso si el
      // comando pudo guardar y falló al entregar su respuesta.
      _ownDialogDepth++;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Error de lectura'),
            content: const Text(
              'No se pudo confirmar el agregado. Revisa la venta; '
              'la lectura fallida no se reintentará. '
              'Los artículos guardados se conservan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
      } finally {
        _ownDialogDepth--;
      }
    }
    if (mounted && identical(_session, session)) {
      setState(() {
        _session = null;
        _closing = false;
      });
    }
    _finishOperation = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_focusChanged);
    _session?.removeListener(_changed);
    // Un desmontaje forzado invalida consultas; las salidas normales esperan
    // finish desde Caja/Home antes de desmontar este widget.
    _session?.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final ready =
        session != null &&
        session.isAccepting &&
        _focus.hasFocus &&
        _available &&
        !_closing;
    final status = _closing
        ? 'Finalizando lecturas…'
        : session?.isPaused == true || !ready
        ? 'Lector en pausa'
        : session.isSaving
        ? 'Guardando…'
        : 'Listo para escanear';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                const Expanded(child: Text('Lector físico')),
                Switch(
                  key: const Key('physical_barcode_toggle'),
                  value: session != null,
                  onChanged: _closing || !widget.interactionEnabled
                      ? null
                      : (enabled) {
                          if (enabled) {
                            enableReader();
                          } else {
                            unawaited(finish());
                          }
                        },
                ),
              ],
            ),
          ),
          if (session != null) ...[
            TextField(
              key: const Key('physical_barcode_input'),
              controller: _text,
              focusNode: _focus,
              readOnly: _closing || !widget.interactionEnabled,
              textInputAction: TextInputAction.done,
              onEditingComplete: () {},
              onSubmitted: _submit,
              onTap: _resume,
              decoration: const InputDecoration(
                labelText: 'Escanea un código y envía Enter',
                border: OutlineInputBorder(),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                '$status · ${session.pendingReadCount} lecturas pendientes',
                key: const Key('physical_barcode_status'),
              ),
            ),
            if (session.error != null)
              const Text(
                'No se pudo agregar el artículo. Reanuda las otras lecturas; '
                'la intención fallida no se reintentará.',
              )
            else if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            if (!ready && !_closing && _ownDialogDepth == 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _available ? _resume : null,
                  child: const Text('Reanudar lector'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
