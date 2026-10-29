import 'package:flutter/material.dart';

/// Texto derivado del margen promedio de una tarjeta de gestión del inventario.
///
/// El porcentaje llega sin redondear; aquí solo se formatea para mostrar.
class InventoryMarginLabel extends StatelessWidget {
  const InventoryMarginLabel({
    required this.porcentaje,
    this.loading = false,
    this.hasError = false,
    super.key,
  });

  final double? porcentaje;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _texto(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _texto() {
    if (loading) return 'Margen promedio: Cargando...';
    if (hasError) return 'Margen promedio: No disponible';
    final value = porcentaje;
    if (value == null) return 'Margen promedio: Sin datos';
    return 'Margen promedio: ${value.toStringAsFixed(1)} %';
  }
}
