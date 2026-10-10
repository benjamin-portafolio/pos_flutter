import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../domain/articulos/codigo_barras.dart';
import 'barcode_read_gate.dart';

/// Lector mínimo de fase 1, accesible por la entrada de diagnóstico en tool/.
/// [onRead] abarca toda la operación serializada y devuelve su resultado visible.
/// No está conectado a Caja ni modifica el lector String? del editor.
class BarcodeReadProbeScreen extends StatefulWidget {
  const BarcodeReadProbeScreen({
    required this.onRead,
    this.readGate,
    super.key,
  });

  final Future<String> Function(String codigo) onRead;
  final BarcodeReadGate? readGate;

  @override
  State<BarcodeReadProbeScreen> createState() => _BarcodeReadProbeScreenState();
}

class _BarcodeReadProbeScreenState extends State<BarcodeReadProbeScreen>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  late final _gate =
      widget.readGate ?? BarcodeReadGate(clock: () => _clock.elapsed);
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
  bool _busy = false;
  bool _closing = false;
  bool _disposed = false;
  bool _ambiguous = false;
  String _message = 'Enfoca una etiqueta dentro del marco.';
  String? _cameraError;

  bool get _wantsCamera =>
      !_disposed &&
      !_closing &&
      _appActive &&
      _routeActive &&
      _cameraError == null;

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
    // Esta dependencia también notifica diálogos y otras rutas que cubren el lector.
    final active = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeActive == active) return;
    _routeActive = active;
    _gate.setCameraActive(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCamera());
  }

  void _cameraChanged() {
    _gate.setCameraActive(_wantsCamera && _controller.value.isRunning);
  }

  /// Inicio/parada/dispose se encadenan, incluso con un permiso pendiente.
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
      } catch (_) {
        _gate.setCameraActive(false);
        if (mounted && !_closing) {
          setState(
            () => _cameraError =
                'No se pudo iniciar la cámara. Revisa el permiso y vuelve a abrir el lector.',
          );
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _gate.setCameraActive(false);
    if (_controller.value.hasCameraPermission) _updateCamera();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_wantsCamera || !_controller.value.isRunning) return;
    final codes = <String>{};
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final code = CodigoBarras.fromInput(raw).value;
        if (code != null) codes.add(code);
      } on ArgumentError {
        // Identidad de la presentación inválida, sin ampliar CodigoBarras.
        codes.add('\u0000$raw');
      }
    }
    final accepted = _gate.observe(codes, admissionEnabled: !_busy);
    if (codes.length > 1) {
      if (!_ambiguous && !_busy) {
        setState(() => _message = 'Enfoca un solo código dentro del marco.');
      }
      // Si el guardado aún ocupa la UI, mostrar el aviso en el siguiente
      // callback libre, sin perder las observaciones de presencia.
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
      _message = 'Procesando $accepted…';
    });
    _readOperation = _read(accepted);
  }

  Future<void> _read(String code) async {
    try {
      final message = await widget.onRead(code);
      if (mounted && !_closing) setState(() => _message = message);
    } catch (_) {
      if (mounted && !_closing) {
        setState(
          () => _message =
              'No se pudo procesar el código. Retira la etiqueta antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    _gate.setCameraActive(false);
    _updateCamera();
    // Cerrar no promete rollback: espera cualquier operación ya iniciada.
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
        debugPrint('No se pudo liberar la cámara del prototipo: $error');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy,
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
      appBar: AppBar(
        title: const Text('Prueba de lecturas'),
        leading: IconButton(
          key: const Key('close_read_probe'),
          onPressed: _closing ? null : _close,
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scanWindow = Rect.fromCenter(
                  center: constraints.biggest.center(Offset.zero),
                  width: constraints.maxWidth * .85,
                  height: constraints.maxHeight * .35,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      useAppLifecycleState: false,
                      scanWindow: scanWindow,
                      onDetect: _onDetect,
                      onDetectError: (_, _) {
                        _gate.setCameraActive(false);
                        if (mounted && !_closing) {
                          setState(
                            () => _cameraError =
                                'Se interrumpió la cámara. Vuelve a abrir el lector.',
                          );
                          _updateCamera();
                        }
                      },
                      errorBuilder: (_, _) => const Center(
                        child: Text(
                          'Cámara no disponible. Revisa el permiso del dispositivo.',
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: scanWindow,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _cameraError ??
                    (_closing
                        ? 'Esperando la operación para cerrar…'
                        : _message),
                key: const Key('read_probe_status'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
