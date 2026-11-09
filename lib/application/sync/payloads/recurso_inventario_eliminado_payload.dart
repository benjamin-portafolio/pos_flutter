/// Baja lógica: conserva identidad, balance e historial del recurso.
class RecursoInventarioEliminadoPayload {
  const RecursoInventarioEliminadoPayload._(this.baseEventId);

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_eliminado';
  final String baseEventId;

  factory RecursoInventarioEliminadoPayload.create({
    required String baseEventId,
  }) => RecursoInventarioEliminadoPayload.fromJson({
    'base_event_id': baseEventId,
  });

  factory RecursoInventarioEliminadoPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final base = json['base_event_id'];
    if (json.length != 1 ||
        base is! String ||
        base.trim().isEmpty ||
        base.trim().length > 120) {
      throw const FormatException(
        'La eliminación requiere únicamente base_event_id válido.',
      );
    }
    return RecursoInventarioEliminadoPayload._(base.trim());
  }

  Map<String, Object?> toJson() => {'base_event_id': baseEventId};
}
