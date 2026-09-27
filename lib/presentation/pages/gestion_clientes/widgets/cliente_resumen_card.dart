import 'package:flutter/material.dart';

import '../../../../domain/clientes/cliente_resumen.dart';
import '../models/cliente_resumen_display.dart';

/// Tarjeta compacta de cliente del listado de Gestión de clientes.
///
/// Muestra avatar con la inicial, nombre y teléfono, cantidad de compras,
/// último movimiento y estado de cuenta. En la pestaña de adeudos se destaca
/// a la derecha el importe pendiente.
class ClienteResumenCard extends StatelessWidget {
  const ClienteResumenCard({
    required this.resumen,
    required this.onTap,
    this.destacarAdeudo = false,
    super.key,
  });

  final ClienteResumen resumen;
  final VoidCallback onTap;

  /// Resalta el importe adeudado a la derecha (pestaña Clientes con adeudo).
  final bool destacarAdeudo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estado = ClienteResumenDisplay.estadoDeCuenta(resumen.saldoMinor);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  _inicial(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resumen.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resumen.telefono ?? 'Sin teléfono',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!resumen.active) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cuenta con incidencia · consultar historial',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _meta(
                          theme,
                          Icons.receipt_long_outlined,
                          'Compras: ${resumen.compras}',
                        ),
                        _meta(
                          theme,
                          Icons.schedule,
                          ClienteResumenDisplay.ultimoMovimientoLabel(
                            resumen.ultimoMovimiento,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      estado.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ClienteResumenDisplay.colorDe(
                          estado.estado,
                          theme,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (destacarAdeudo && resumen.saldoMinor.isNegative) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'DEBE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ClienteResumenDisplay.money(resumen.saldoMinor.abs()),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _inicial() {
    final nombre = resumen.nombre.trim();
    return nombre.isEmpty ? '?' : nombre.substring(0, 1).toUpperCase();
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}