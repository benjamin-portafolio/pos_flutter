import 'package:flutter/material.dart';

class ManagementDialogHeader extends StatelessWidget {
  const ManagementDialogHeader({
    super.key,
    required this.titulo,
    required this.textoBoton,
    required this.onConfirmar,
    this.colorBoton = const Color(0xFF66BB6A),
  });

  final String titulo;
  final String textoBoton;
  final VoidCallback onConfirmar;
  final Color colorBoton;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorBoton,
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: onConfirmar,
          child: Text(textoBoton, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
