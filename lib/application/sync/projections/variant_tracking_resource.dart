import 'variant_tracking_balance.dart';

/// Recurso y su unidad, con la información mínima que necesita el contrato para
/// decidir recuperación, elegibilidad y la selección legada.
class VariantTrackingResource {
  const VariantTrackingResource({
    required this.id,
    required this.name,
    required this.defaultUnitId,
    required this.originVariantId,
    required this.active,
    required this.version,
    required this.createdEventId,
    required this.lastServerSequence,
    this.unitName,
    this.balance,
  });

  final String id;
  final String name;
  final String defaultUnitId;

  /// Procedencia declarada en el alta del recurso. `null` significa desconocido
  /// y nunca autoriza limpieza ni define un candidato único.
  final String? originVariantId;
  final String? unitName;
  final VariantTrackingBalance? balance;
  final bool active;
  final int version;
  final String? createdEventId;
  final int? lastServerSequence;
}
