import 'package:flutter/material.dart';

import 'physical_barcode_reader_controller.dart';

/// Mantiene una salida visible si una pausa/error impide terminar el drenaje.
class PhysicalBarcodeFinishDialog extends StatelessWidget {
  const PhysicalBarcodeFinishDialog({
    required this.controller,
    required this.onResume,
    super.key,
  });

  final PhysicalBarcodeReaderController controller;
  final VoidCallback onResume;

  Future<void> _discard(BuildContext context) async {
    // Congelar los pasos aún no iniciados mantiene estable el número mostrado.
    controller.pause();
    final count = controller.unstartedReadCount;
    if (count == 0) {
      await controller.finish(discardPending: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar lecturas pendientes'),
        content: Text(
          'Se perderán $count intenciones que aún no iniciaron su guardado. '
          'Los artículos guardados se conservan. Un guardado en curso terminará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Descartar $count lecturas'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.finish(discardPending: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AlertDialog(
        title: const Text('Finalizando lecturas'),
        content: Text(
          controller.error != null
              ? 'No se pudo agregar el artículo. Reanuda las otras lecturas '
                    'o descarta lo pendiente. La intención fallida no se reintentará.'
              : 'Esperando las lecturas aceptadas. '
                    '${controller.unstartedReadCount} sin iniciar guardado.'
                    '${controller.isPaused ? " Lector en pausa." : ""}',
        ),
        actions: [
          if (controller.isPaused)
            TextButton(
              onPressed: onResume,
              child: const Text('Reanudar pendientes'),
            ),
          TextButton(
            onPressed: () => _discard(context),
            child: const Text('Descartar pendientes…'),
          ),
        ],
      ),
    ),
  );
}
