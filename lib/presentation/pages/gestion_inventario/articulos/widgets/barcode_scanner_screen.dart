import 'package:flutter/material.dart';

/// Pantalla de escaneo de código de barras, todavía sin cámara.
///
/// Contrato de ida y vuelta (estable; si cambia, hay que actualizar al
/// consumidor en `variant_editor_screen.dart`):
/// - `Navigator.of(context).pop(codigo)` devuelve el código leído como
///   `String`. Nunca `int`: un tipo numérico destruiría los ceros a la
///   izquierda de un UPC-A y no podría representar GS1-128.
/// - `Navigator.of(context).pop()` sin argumentos devuelve `null`; el
///   consumidor lo interpreta como cancelación y deja el campo intacto.
///
/// Lo que falta: el preview de cámara y la lectura del código, que requieren
/// `mobile_scanner`. Ese paquete no está en `pubspec.yaml` a propósito, para que
/// este paso no agregue dependencias ni permisos de plataforma. Mientras tanto,
/// la captura por teclado en el formulario de variante es el camino funcional.
///
/// Cuando se agregue `mobile_scanner`, el trabajo se limita al interior de esta
/// pantalla: el `AppBar` con el `X`, el fondo y el pie de instrucción no se
/// tocan, y el consumidor sigue funcionando sin cambios.
class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('barcode_scanner_screen'),
      // Fondo liso y opaco: es lo queoccupará el preview de cámara.
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
          // Sin argumentos: el resultado es `null` y el consumidor no toca el
          // campo de código de barras.
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Cerrar',
        ),
      ),
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Text(
              'Escanee el código de barras aquí para actualizar artículos o '
              'crear nuevos.',
              key: const Key('barcode_scanner_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}
