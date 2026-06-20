import 'package:flutter/material.dart';

class AddOptionsBottomSheet extends StatelessWidget {
  const AddOptionsBottomSheet({
    super.key,
    required this.onAgregarMesa,
    required this.onAgregarEspacio,
  });

  final VoidCallback onAgregarMesa;
  final VoidCallback onAgregarEspacio;

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onAgregarMesa,
    required VoidCallback onAgregarEspacio,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => AddOptionsBottomSheet(
        onAgregarMesa: onAgregarMesa,
        onAgregarEspacio: onAgregarEspacio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Row(
        children: [
          Expanded(
            child: _OpcionMenu(
              texto: 'Agregar mesa',
              onTap: () {
                Navigator.of(context).pop();
                onAgregarMesa();
              },
            ),
          ),
          Expanded(
            child: _OpcionMenu(
              texto: 'Agregar espacio',
              onTap: () {
                Navigator.of(context).pop();
                onAgregarEspacio();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OpcionMenu extends StatelessWidget {
  const _OpcionMenu({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Text(
          texto,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
