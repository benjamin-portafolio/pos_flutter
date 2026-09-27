import 'financial_direction.dart';
import 'financial_nature.dart';

/// Registro real de ingreso o gasto adicional para la UI. Modelo de consulta
/// sin Drift. Conserva snapshots de la categoría, `currency = 'MXN'` fija,
/// y el estado/motivo de entrega: una incidencia de entrega (`deliveryStatus`
/// distinto de `delivered`) no oculta ni revierte el dinero ya registrado.
class FinancialEntry {
  const FinancialEntry({
    required this.id,
    required this.categoryId,
    required this.categoryNameSnapshot,
    required this.direction,
    required this.nature,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.occurredAtMs,
    this.notes,
    this.reference,
    required this.deliveryStatus,
    this.rejectionReason,
    required this.eventId,
    required this.userId,
    required this.deviceId,
  });

  final String id;
  final String categoryId;
  final String categoryNameSnapshot;
  final FinancialDirection direction;
  final FinancialNature nature;

  /// Importe en centavos (entero positivo, entero seguro).
  final int amountMinor;

  /// Moneda fija `MXN`.
  final String currency;

  /// Medio `cash` | `transfer` (string, convención del código actual).
  final String method;

  /// Instante efectivo UTC en ms, filtra períodos `[fromMs, toMs)`.
  final int occurredAtMs;
  final String? notes;
  final String? reference;

  /// Estado de entrega del evento (`not_required` | `pending` | `delivered` |
  /// `rejected` | `conflict`). No es estado del dinero.
  final String deliveryStatus;
  final String? rejectionReason;
  final String eventId;
  final String userId;
  final String deviceId;
}