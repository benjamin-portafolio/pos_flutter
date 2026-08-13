import '../../../domain/categorias/color_categoria.dart';

class CategoriaEliminadaPayload {
  const CategoriaEliminadaPayload({
    required this.baseEventId,
    required this.categoriaEliminada,
    required this.categoriasDesplazadas,
  });

  static const aggregateType = 'category';
  static const eventType = 'categoria_eliminada';

  final String baseEventId;
  final CategoriaEliminadaSnapshot categoriaEliminada;
  final List<CategoriaEliminadaCategoriaDesplazada> categoriasDesplazadas;

  factory CategoriaEliminadaPayload.fromJson(Map<String, Object?> json) {
    final deleted = _readMap(json['deleted_category'], 'deleted_category');
    final resolution = _readMap(
      json['product_resolution'],
      'product_resolution',
    );
    if (resolution['type'] != 'none') {
      throw const FormatException(
        'categoria_eliminada solo admite product_resolution.type = none.',
      );
    }

    final linkedProducts = json['linked_products'];
    if (linkedProducts is! List || linkedProducts.isNotEmpty) {
      throw const FormatException(
        'categoria_eliminada requiere linked_products vacío.',
      );
    }

    final rawShifted = json['shifted_categories'];
    if (rawShifted is! List) {
      throw const FormatException(
        'categoria_eliminada requiere shifted_categories como arreglo.',
      );
    }

    final snapshot = CategoriaEliminadaSnapshot(
      nombre: _readRequiredString(deleted['name'], 'deleted_category.name'),
      color: _readColor(deleted['color_key']),
      orden: _readNonNegativeInt(
        deleted['sort_order'],
        'deleted_category.sort_order',
      ),
      active: _readBool(deleted['active'], 'deleted_category.active'),
      createdEventId: _readRequiredString(
        deleted['created_event_id'],
        'deleted_category.created_event_id',
      ),
    );
    final shifted = rawShifted
        .asMap()
        .entries
        .map(
          (entry) => CategoriaEliminadaCategoriaDesplazada.fromJson(
            _readMap(entry.value, 'shifted_categories[${entry.key}]'),
          ),
        )
        .toList(growable: false);

    _validateShifted(snapshot, shifted);
    return CategoriaEliminadaPayload(
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      categoriaEliminada: snapshot,
      categoriasDesplazadas: shifted,
    );
  }

  factory CategoriaEliminadaPayload.fromValues({
    required String baseEventId,
    required CategoriaEliminadaSnapshot categoriaEliminada,
    required List<CategoriaEliminadaCategoriaDesplazada> categoriasDesplazadas,
  }) {
    return CategoriaEliminadaPayload.fromJson({
      'base_event_id': baseEventId,
      'deleted_category': categoriaEliminada.toJson(),
      'product_resolution': const {'type': 'none'},
      'linked_products': const <Object?>[],
      'shifted_categories': categoriasDesplazadas
          .map((category) => category.toJson())
          .toList(growable: false),
    });
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'deleted_category': categoriaEliminada.toJson(),
    'product_resolution': const {'type': 'none'},
    'linked_products': const <Object?>[],
    'shifted_categories': categoriasDesplazadas
        .map((category) => category.toJson())
        .toList(growable: false),
  };

  static void _validateShifted(
    CategoriaEliminadaSnapshot deleted,
    List<CategoriaEliminadaCategoriaDesplazada> shifted,
  ) {
    final ids = <String>{};
    for (var index = 0; index < shifted.length; index++) {
      final category = shifted[index];
      final expectedFrom = deleted.orden + index + 1;
      if (!ids.add(category.categoriaId)) {
        throw const FormatException(
          'shifted_categories no puede repetir categorías.',
        );
      }
      if (category.ordenAnterior != expectedFrom ||
          category.ordenNuevo != expectedFrom - 1) {
        throw const FormatException(
          'shifted_categories debe contener posiciones consecutivas y to = from - 1.',
        );
      }
    }
  }
}

class CategoriaEliminadaSnapshot {
  const CategoriaEliminadaSnapshot({
    required this.nombre,
    required this.color,
    required this.orden,
    required this.active,
    required this.createdEventId,
  });

  final String nombre;
  final ColorCategoria color;
  final int orden;
  final bool active;
  final String createdEventId;

  Map<String, Object?> toJson() => {
    'name': nombre,
    'color_key': color.key,
    'sort_order': orden,
    'active': active,
    'created_event_id': createdEventId,
  };
}

class CategoriaEliminadaCategoriaDesplazada {
  const CategoriaEliminadaCategoriaDesplazada({
    required this.categoriaId,
    required this.baseEventId,
    required this.baseVersion,
    required this.baseServerSequence,
    required this.ordenAnterior,
    required this.ordenNuevo,
  });

  final String categoriaId;
  final String baseEventId;
  final int baseVersion;
  final int? baseServerSequence;
  final int ordenAnterior;
  final int ordenNuevo;

  factory CategoriaEliminadaCategoriaDesplazada.fromJson(
    Map<String, Object?> json,
  ) {
    final sortOrder = _readMap(json['sort_order'], 'sort_order');
    final from = _readNonNegativeInt(sortOrder['from'], 'sort_order.from');
    final to = _readNonNegativeInt(sortOrder['to'], 'sort_order.to');
    if (to != from - 1) {
      throw const FormatException(
        'Cada categoría desplazada debe cumplir to = from - 1.',
      );
    }
    return CategoriaEliminadaCategoriaDesplazada(
      categoriaId: _readRequiredString(json['category_id'], 'category_id'),
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      baseVersion: _readPositiveInt(json['base_version'], 'base_version'),
      baseServerSequence: _readNullableNonNegativeInt(
        json['base_server_sequence'],
        'base_server_sequence',
      ),
      ordenAnterior: from,
      ordenNuevo: to,
    );
  }

  Map<String, Object?> toJson() => {
    'category_id': categoriaId,
    'base_event_id': baseEventId,
    'base_version': baseVersion,
    'base_server_sequence': baseServerSequence,
    'sort_order': {'from': ordenAnterior, 'to': ordenNuevo},
  };
}

Map<String, Object?> _readMap(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('categoria_eliminada requiere $field como objeto.');
}

String _readRequiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('categoria_eliminada requiere $field.');
  }
  return value.trim();
}

ColorCategoria _readColor(Object? value) {
  if (value is! String) {
    throw const FormatException('deleted_category.color_key debe ser string.');
  }
  try {
    return ColorCategoria.fromKey(value);
  } on ArgumentError catch (_) {
    throw const FormatException(
      'deleted_category.color_key no pertenece a la paleta.',
    );
  }
}

bool _readBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('categoria_eliminada requiere $field booleano.');
  }
  return value;
}

int _readNonNegativeInt(Object? value, String field) {
  final parsed = _readInt(value);
  if (parsed == null || parsed < 0) {
    throw FormatException('categoria_eliminada requiere $field entero >= 0.');
  }
  return parsed;
}

int _readPositiveInt(Object? value, String field) {
  final parsed = _readInt(value);
  if (parsed == null || parsed < 1) {
    throw FormatException('categoria_eliminada requiere $field entero >= 1.');
  }
  return parsed;
}

int? _readNullableNonNegativeInt(Object? value, String field) {
  if (value == null) return null;
  return _readNonNegativeInt(value, field);
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}
