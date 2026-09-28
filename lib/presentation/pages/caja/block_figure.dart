import 'package:flutter/material.dart';

/// Una cifra de un bloque de la pantalla de caja.
///
/// Comparte la escala visual del `_total` de `cash_session_content.dart`
/// (24 px, w600) para que efectivo, transferencias y saldo en cuenta se
/// comparen de un vistazo. Lo usan el bloque de transferencias y el de saldo
/// en cuenta: dos bloques con la misma escala, etiquetas distintas.
class BlockFigure extends StatelessWidget {
  const BlockFigure({
    super.key,
    required this.label,
    required this.value,
    this.destacado = false,
  });

  final String label;
  final String value;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: destacado ? theme.textTheme.titleSmall : null),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: destacado ? 28 : 24,
            fontWeight: destacado ? FontWeight.w700 : FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}