import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Captura un código de barras con la cámara y lo devuelve al formulario.
///
/// Devuelve un `String` para conservar los ceros iniciales. Cancelar devuelve
/// `null`; el editor conserva entonces el campo y sigue siendo responsable de
/// validar y guardar el código, igual que en la captura manual.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(autoStart: false);
  Future<void> _cameraOperation = Future.value();
  MobileScannerException? _cameraError;
  bool _appActive = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCamera());
  }

  /// Serializa inicio y parada, incluso si se cierra el lector mientras el
  /// sistema todavía solicita permiso. La cámara se libera al terminar el inicio.
  void _updateCamera() {
    _cameraOperation = _cameraOperation.then((_) async {
      try {
        if (!mounted || _finished || !_appActive) {
          await _controller.stop();
          return;
        }
        if (_cameraError != null) setState(() => _cameraError = null);
        await _controller.start();
        if (!mounted || _finished || !_appActive) {
          await _controller.stop();
        }
      } on Exception catch (error) {
        if (!mounted || _finished) return;
        setState(() {
          _cameraError = error is MobileScannerException
              ? error
              : const MobileScannerException(
                  errorCode: MobileScannerErrorCode.genericError,
                );
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    // Los diálogos de permisos también cambian el ciclo de vida. El inicio
    // pendiente se encarga de parar si la app ya no está activa al terminar.
    if (_controller.value.hasCameraPermission) _updateCamera();
  }

  @override
  void dispose() {
    _finished = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _cameraOperation.whenComplete(_controller.dispose).onError<Exception>((
        error,
        stackTrace,
      ) {
        // Al salir ya no hay una pantalla donde mostrar un fallo nativo de
        // limpieza; no debe impedir volver al formulario ni capturar manualmente.
        debugPrint('No se pudo liberar la cámara del lector: $error');
      }),
    );
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finished ||
        !mounted ||
        !_appActive ||
        !_controller.value.isRunning ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.trim().isEmpty) continue;

      // Una cámara puede emitir varias lecturas antes de terminar la animación
      // de salida. Solo la primera debe cerrar esta ruta.
      _finished = true;
      _updateCamera();
      Navigator.of(context).pop(code);
      return;
    }
  }

  void _close() {
    if (_finished) return;
    _finished = true;
    _updateCamera();
    Navigator.of(context).pop();
  }

  Widget _buildCameraError(BuildContext context, MobileScannerException error) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permite el acceso a la cámara en los ajustes del dispositivo y vuelve '
            'a abrir el lector. También puedes capturar el código manualmente.',
      MobileScannerErrorCode.unsupported =>
        'No hay una cámara disponible para escanear en este dispositivo. '
            'Captura el código manualmente.',
      _ =>
        'No se pudo iniciar la cámara. Cierra el lector e inténtalo de nuevo, '
            'o captura el código manualmente.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Text(
          message,
          key: const Key('barcode_scanner_error'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _finished = true;
          _updateCamera();
        }
      },
      child: Scaffold(
        key: const Key('barcode_scanner_screen'),
        backgroundColor: const Color(0xFF101010),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          leading: IconButton(
            key: const Key('close_barcode_scanner_button'),
            onPressed: _close,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Cerrar',
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraError case final error?)
              _buildCameraError(context, error)
            else
              MobileScanner(
                key: const Key('barcode_scanner_camera'),
                controller: _controller,
                useAppLifecycleState: false,
                onDetect: _onDetect,
                errorBuilder: _buildCameraError,
                placeholderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Escanee el código de barras aquí para actualizar artículos o '
                        'crear nuevos.',
                        key: const Key('barcode_scanner_hint'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
