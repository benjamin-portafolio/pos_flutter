import '../../../domain/categorias/color_categoria.dart';

class CategoriaActualizadaPayload {
  const CategoriaActualizadaPayload._({
    required this.baseEventId,
    required this.nombreAnterior,
    required this.nombreNuevo,
    required this.colorAnterior,
    required this.colorNuevo,
  });

  static const aggregateType = 'category';
  static const eventType = 'categoria_actualizada';
  static const nameField = 'name';
  static const colorKeyField = 'color_key';

  final String baseEventId;
  final String? nombreAnterior;
  final String? nombreNuevo;
  final ColorCategoria? colorAnterior;
  final ColorCategoria? colorNuevo;

  bool get cambiaNombre => nombreAnterior != null;
  bool get cambiaColor => colorAnterior != null;
  bool get tieneCambios => cambiaNombre || cambiaColor;

  List<String> get changedFields => [
    if (cambiaNombre) nameField,
    if (cambiaColor) colorKeyField,
  ];

  factory CategoriaActualizadaPayload.fromValues({
    required String baseEventId,
    required String nombreAnterior,
    required String nombreNuevo,
    required ColorCategoria colorAnterior,
    required ColorCategoria colorNuevo,
  }) {
    final normalizedBaseEventId = _readBaseEventId(baseEventId);
    final previousName = _readRequiredName(nombreAnterior, nameField, 'from');
    final nextName = _readRequiredName(nombreNuevo, nameField, 'to');

    return CategoriaActualizadaPayload._(
      baseEventId: normalizedBaseEventId,
      nombreAnterior: previousName == nextName ? null : previousName,
      nombreNuevo: previousName == nextName ? null : nextName,
      colorAnterior: colorAnterior == colorNuevo ? null : colorAnterior,
      colorNuevo: colorAnterior == colorNuevo ? null : colorNuevo,
    );
  }

  factory CategoriaActualizadaPayload.fromJson(Map<String, Object?> json) {
    final baseEventId = _readBaseEventId(json['base_event_id']);
    final changedFields = _readChangedFields(json['changed_fields']);
    final changes = _readChanges(json['changes']);

    String? previousName;
    String? nextName;
    ColorCategoria? previousColor;
    ColorCategoria? nextColor;

    if (changedFields.contains(nameField)) {
      final change = _readFieldChange(changes, nameField);
      previousName = _readRequiredName(change['from'], nameField, 'from');
      nextName = _readRequiredName(change['to'], nameField, 'to');
      if (previousName == nextName) {
        throw const FormatException(
          'categoria_actualizada no puede declarar name sin modificarlo.',
        );
      }
    }

    if (changedFields.contains(colorKeyField)) {
      final change = _readFieldChange(changes, colorKeyField);
      previousColor = _readColor(change['from'], colorKeyField, 'from');
      nextColor = _readColor(change['to'], colorKeyField, 'to');
      if (previousColor == nextColor) {
        throw const FormatException(
          'categoria_actualizada no puede declarar color_key sin modificarlo.',
        );
      }
    }

    return CategoriaActualizadaPayload._(
      baseEventId: baseEventId,
      nombreAnterior: previousName,
      nombreNuevo: nextName,
      colorAnterior: previousColor,
      colorNuevo: nextColor,
    );
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'changed_fields': changedFields,
    'changes': {
      if (cambiaNombre) nameField: {'from': nombreAnterior, 'to': nombreNuevo},
      if (cambiaColor)
        colorKeyField: {'from': colorAnterior!.key, 'to': colorNuevo!.key},
    },
  };

  static String _readBaseEventId(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException(
        'categoria_actualizada requiere payload.base_event_id.',
      );
    }
    return value.trim();
  }

  static List<String> _readChangedFields(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException(
        'categoria_actualizada requiere payload.changed_fields.',
      );
    }

    final fields = <String>[];
    for (final field in value) {
      if (field is! String ||
          (field != nameField && field != colorKeyField) ||
          fields.contains(field)) {
        throw const FormatException(
          'categoria_actualizada contiene changed_fields invalidos.',
        );
      }
      fields.add(field);
    }
    return fields;
  }

  static Map<String, Object?> _readChanges(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException(
      'categoria_actualizada requiere payload.changes.',
    );
  }

  static Map<String, Object?> _readFieldChange(
    Map<String, Object?> changes,
    String field,
  ) {
    final value = changes[field];
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException(
      'categoria_actualizada requiere payload.changes.$field.',
    );
  }

  static String _readRequiredName(Object? value, String field, String edge) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'categoria_actualizada requiere changes.$field.$edge.',
      );
    }
    return value.trim();
  }

  static ColorCategoria _readColor(Object? value, String field, String edge) {
    if (value is! String) {
      throw FormatException(
        'categoria_actualizada requiere changes.$field.$edge.',
      );
    }
    return ColorCategoria.fromKey(value);
  }
}
