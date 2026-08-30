import '../../../domain/inventario/nombre_recurso_inventario.dart';

class RecursoInventarioActualizadoPayload {
  const RecursoInventarioActualizadoPayload._({
    required this.baseEventId,
    required this.previousName,
    required this.nextName,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_actualizado';
  static const nameField = 'name';

  final String baseEventId;
  final String previousName;
  final String nextName;

  factory RecursoInventarioActualizadoPayload.create({
    required String baseEventId,
    required String previousName,
    required String nextName,
  }) {
    final previous = NombreRecursoInventario.fromInput(previousName).value;
    final next = NombreRecursoInventario.fromInput(nextName).value;
    if (previous == next) {
      throw const FormatException(
        'recurso_inventario_actualizado debe cambiar el nombre.',
      );
    }
    return RecursoInventarioActualizadoPayload._(
      baseEventId: _requiredText(baseEventId, 'base_event_id'),
      previousName: previous,
      nextName: next,
    );
  }

  factory RecursoInventarioActualizadoPayload.fromJson(
    Map<String, Object?> json,
  ) {
    _assertOnlyKeys(json, const {
      'base_event_id',
      'changed_fields',
      'changes',
    });
    final fields = json['changed_fields'];
    if (fields is! List || fields.length != 1 || fields.single != nameField) {
      throw const FormatException(
        'recurso_inventario_actualizado solo admite changed_fields = [name].',
      );
    }
    final changes = _requiredMap(json['changes'], 'changes');
    _assertOnlyKeys(changes, const {nameField}, fieldName: 'changes');
    final name = _requiredMap(changes[nameField], 'changes.name');
    _assertOnlyKeys(name, const {'from', 'to'}, fieldName: 'changes.name');
    return RecursoInventarioActualizadoPayload.create(
      baseEventId: _requiredText(json['base_event_id'], 'base_event_id'),
      previousName: _requiredText(name['from'], 'changes.name.from'),
      nextName: _requiredText(name['to'], 'changes.name.to'),
    );
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'changed_fields': const [nameField],
    'changes': {
      nameField: {'from': previousName, 'to': nextName},
    },
  };
}

void _assertOnlyKeys(
  Map<String, Object?> value,
  Set<String> allowed, {
  String fieldName = 'recurso_inventario_actualizado',
}) {
  final unexpected = value.keys.where((key) => !allowed.contains(key)).toList();
  if (unexpected.isNotEmpty) {
    throw FormatException(
      '$fieldName contiene campos no permitidos: ${unexpected.join(', ')}.',
    );
  }
}

Map<String, Object?> _requiredMap(Object? value, String fieldName) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$fieldName debe ser un objeto.');
}

String _requiredText(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName es obligatorio.');
  }
  return value.trim();
}
