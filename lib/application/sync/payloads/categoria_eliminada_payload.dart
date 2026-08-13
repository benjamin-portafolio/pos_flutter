import '../../../domain/categorias/color_categoria.dart';

enum CategoriaEliminadaResolucionTipo {
  none('none'),
  move('move'),
  uncategorize('uncategorize');

  const CategoriaEliminadaResolucionTipo(this.value);

  final String value;
}

class CategoriaEliminadaPayload {
  const CategoriaEliminadaPayload({
    required this.baseEventId,
    required this.categoriaEliminada,
    required this.resolucionProductos,
    required this.productosVinculados,
    required this.categoriasDesplazadas,
  });

  static const aggregateType = 'category';
  static const eventType = 'categoria_eliminada';

  final String baseEventId;
  final CategoriaEliminadaSnapshot categoriaEliminada;
  final CategoriaEliminadaResolucion resolucionProductos;
  final List<CategoriaEliminadaProductoVinculado> productosVinculados;
  final List<CategoriaEliminadaCategoriaDesplazada> categoriasDesplazadas;

  factory CategoriaEliminadaPayload.fromJson(Map<String, Object?> json) {
    final deleted = _readMap(json['deleted_category'], 'deleted_category');
    final resolution = CategoriaEliminadaResolucion.fromJson(
      _readMap(json['product_resolution'], 'product_resolution'),
    );
    final rawLinked = json['linked_products'];
    if (rawLinked is! List) {
      throw const FormatException(
        'categoria_eliminada requiere linked_products como arreglo.',
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
    final linked = rawLinked
        .asMap()
        .entries
        .map(
          (entry) => CategoriaEliminadaProductoVinculado.fromJson(
            _readMap(entry.value, 'linked_products[${entry.key}]'),
          ),
        )
        .toList(growable: false);
    final shifted = rawShifted
        .asMap()
        .entries
        .map(
          (entry) => CategoriaEliminadaCategoriaDesplazada.fromJson(
            _readMap(entry.value, 'shifted_categories[${entry.key}]'),
          ),
        )
        .toList(growable: false);

    _validateLinked(resolution, linked);
    _validateShifted(snapshot, shifted);
    return CategoriaEliminadaPayload(
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      categoriaEliminada: snapshot,
      resolucionProductos: resolution,
      productosVinculados: linked,
      categoriasDesplazadas: shifted,
    );
  }

  factory CategoriaEliminadaPayload.fromValues({
    required String baseEventId,
    required CategoriaEliminadaSnapshot categoriaEliminada,
    CategoriaEliminadaResolucion resolucionProductos =
        const CategoriaEliminadaResolucion.none(),
    List<CategoriaEliminadaProductoVinculado> productosVinculados = const [],
    required List<CategoriaEliminadaCategoriaDesplazada> categoriasDesplazadas,
  }) {
    return CategoriaEliminadaPayload.fromJson({
      'base_event_id': baseEventId,
      'deleted_category': categoriaEliminada.toJson(),
      'product_resolution': resolucionProductos.toJson(),
      'linked_products': productosVinculados
          .map((product) => product.toJson())
          .toList(growable: false),
      'shifted_categories': categoriasDesplazadas
          .map((category) => category.toJson())
          .toList(growable: false),
    });
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'deleted_category': categoriaEliminada.toJson(),
    'product_resolution': resolucionProductos.toJson(),
    'linked_products': productosVinculados
        .map((product) => product.toJson())
        .toList(growable: false),
    'shifted_categories': categoriasDesplazadas
        .map((category) => category.toJson())
        .toList(growable: false),
  };

  void validateForSourceCategory(String sourceCategoryId) {
    final source = _readRequiredString(sourceCategoryId, 'source_category_id');
    final destination = resolucionProductos.categoriaDestino;
    if (destination?.categoriaId == source) {
      throw const FormatException(
        'La categoría destino debe ser diferente de la categoría eliminada.',
      );
    }
    if (productosVinculados.any(
      (product) => product.categoriaAnteriorId != source,
    )) {
      throw const FormatException(
        'linked_products.category_id.from debe ser la categoría eliminada.',
      );
    }
  }

  static void _validateLinked(
    CategoriaEliminadaResolucion resolution,
    List<CategoriaEliminadaProductoVinculado> linked,
  ) {
    String? previousId;
    for (final product in linked) {
      if (previousId != null && previousId.compareTo(product.productoId) >= 0) {
        throw const FormatException(
          'linked_products debe estar ordenado por product_id y no repetir IDs.',
        );
      }
      previousId = product.productoId;
    }

    switch (resolution.tipo) {
      case CategoriaEliminadaResolucionTipo.none:
        if (linked.isNotEmpty) {
          throw const FormatException(
            'La resolución none requiere linked_products vacío.',
          );
        }
      case CategoriaEliminadaResolucionTipo.move:
        final destinationId = resolution.categoriaDestino!.categoriaId;
        if (linked.any(
          (product) => product.categoriaNuevaId != destinationId,
        )) {
          throw const FormatException(
            'Todos los productos movidos deben usar la categoría destino.',
          );
        }
      case CategoriaEliminadaResolucionTipo.uncategorize:
        if (linked.any((product) => product.categoriaNuevaId != null)) {
          throw const FormatException(
            'La resolución uncategorize requiere category_id.to = null.',
          );
        }
    }
  }

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

class CategoriaEliminadaResolucion {
  const CategoriaEliminadaResolucion.none()
    : tipo = CategoriaEliminadaResolucionTipo.none,
      categoriaDestino = null;

  const CategoriaEliminadaResolucion.move(
    CategoriaEliminadaCategoriaDestino destination,
  ) : tipo = CategoriaEliminadaResolucionTipo.move,
      categoriaDestino = destination;

  const CategoriaEliminadaResolucion.uncategorize()
    : tipo = CategoriaEliminadaResolucionTipo.uncategorize,
      categoriaDestino = null;

  final CategoriaEliminadaResolucionTipo tipo;
  final CategoriaEliminadaCategoriaDestino? categoriaDestino;

  factory CategoriaEliminadaResolucion.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    if (rawType is! String) {
      throw const FormatException('product_resolution.type debe ser string.');
    }
    switch (rawType) {
      case 'none':
        if (json.containsKey('destination_category')) {
          throw const FormatException(
            'La resolución none no admite destination_category.',
          );
        }
        return const CategoriaEliminadaResolucion.none();
      case 'move':
        if (!json.containsKey('destination_category')) {
          throw const FormatException(
            'La resolución move requiere destination_category.',
          );
        }
        return CategoriaEliminadaResolucion.move(
          CategoriaEliminadaCategoriaDestino.fromJson(
            _readMap(
              json['destination_category'],
              'product_resolution.destination_category',
            ),
          ),
        );
      case 'uncategorize':
        if (json.containsKey('destination_category')) {
          throw const FormatException(
            'La resolución uncategorize no admite destination_category.',
          );
        }
        return const CategoriaEliminadaResolucion.uncategorize();
      default:
        throw const FormatException(
          'product_resolution.type debe ser none, move o uncategorize.',
        );
    }
  }

  Map<String, Object?> toJson() => switch (tipo) {
    CategoriaEliminadaResolucionTipo.none => const {'type': 'none'},
    CategoriaEliminadaResolucionTipo.move => {
      'type': 'move',
      'destination_category': categoriaDestino!.toJson(),
    },
    CategoriaEliminadaResolucionTipo.uncategorize => const {
      'type': 'uncategorize',
    },
  };
}

class CategoriaEliminadaCategoriaDestino {
  const CategoriaEliminadaCategoriaDestino({
    required this.categoriaId,
    required this.baseEventId,
    required this.baseVersion,
    required this.baseServerSequence,
  });

  final String categoriaId;
  final String baseEventId;
  final int baseVersion;
  final int? baseServerSequence;

  factory CategoriaEliminadaCategoriaDestino.fromJson(
    Map<String, Object?> json,
  ) {
    return CategoriaEliminadaCategoriaDestino(
      categoriaId: _readRequiredString(json['category_id'], 'category_id'),
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      baseVersion: _readPositiveInt(json['base_version'], 'base_version'),
      baseServerSequence: _readNullableNonNegativeInt(
        json['base_server_sequence'],
        'base_server_sequence',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'category_id': categoriaId,
    'base_event_id': baseEventId,
    'base_version': baseVersion,
    'base_server_sequence': baseServerSequence,
  };
}

class CategoriaEliminadaProductoVinculado {
  const CategoriaEliminadaProductoVinculado({
    required this.productoId,
    required this.baseEventId,
    required this.baseVersion,
    required this.baseServerSequence,
    required this.categoriaAnteriorId,
    required this.categoriaNuevaId,
  });

  final String productoId;
  final String baseEventId;
  final int baseVersion;
  final int? baseServerSequence;
  final String categoriaAnteriorId;
  final String? categoriaNuevaId;

  factory CategoriaEliminadaProductoVinculado.fromJson(
    Map<String, Object?> json,
  ) {
    final category = _readMap(json['category_id'], 'category_id');
    if (!category.containsKey('from') || !category.containsKey('to')) {
      throw const FormatException(
        'linked_products.category_id requiere from y to.',
      );
    }
    final to = category['to'];
    if (to != null && to is! String) {
      throw const FormatException(
        'linked_products.category_id.to debe ser string o null.',
      );
    }
    return CategoriaEliminadaProductoVinculado(
      productoId: _readRequiredString(json['product_id'], 'product_id'),
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      baseVersion: _readPositiveInt(json['base_version'], 'base_version'),
      baseServerSequence: _readNullableNonNegativeInt(
        json['base_server_sequence'],
        'base_server_sequence',
      ),
      categoriaAnteriorId: _readRequiredString(
        category['from'],
        'category_id.from',
      ),
      categoriaNuevaId: to == null
          ? null
          : _readRequiredString(to, 'category_id.to'),
    );
  }

  Map<String, Object?> toJson() => {
    'product_id': productoId,
    'base_event_id': baseEventId,
    'base_version': baseVersion,
    'base_server_sequence': baseServerSequence,
    'category_id': {'from': categoriaAnteriorId, 'to': categoriaNuevaId},
  };
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
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}
