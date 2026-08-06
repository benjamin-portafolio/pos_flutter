import '../../../domain/articulos/nombre_producto.dart';
import '../../../domain/articulos/precio_venta.dart';

class ProductoCreadoPayload {
  const ProductoCreadoPayload({
    required this.nombre,
    required this.categoriaId,
    required this.variante,
    required this.dependenciaCategoria,
  });

  static const aggregateType = 'product';
  static const eventType = 'producto_creado';

  final String nombre;
  final String? categoriaId;
  final ProductoCreadoVariante variante;
  final ProductoCreadoDependencia? dependenciaCategoria;

  factory ProductoCreadoPayload.simple({
    required String nombre,
    required String? categoriaId,
    required String varianteId,
    required int precioVentaMenor,
    ProductoCreadoDependencia? dependenciaCategoria,
  }) {
    final normalizedName = NombreProducto.fromInput(nombre).value;
    final normalizedCategoryId = _optionalNonEmptyString(
      categoriaId,
      'product.category_id',
    );
    if ((normalizedCategoryId == null) != (dependenciaCategoria == null)) {
      throw const FormatException(
        'La dependencia de categoria debe coincidir con product.category_id.',
      );
    }
    if (dependenciaCategoria?.refId != normalizedCategoryId) {
      throw const FormatException(
        'La dependencia no coincide con product.category_id.',
      );
    }

    return ProductoCreadoPayload(
      nombre: normalizedName,
      categoriaId: normalizedCategoryId,
      variante: ProductoCreadoVariante(
        id: _requiredString(varianteId, 'variants[0].variant_id'),
        precioVentaMenor: PrecioVenta.fromUnidadMenor(
          precioVentaMenor,
        ).unidadMenor,
      ),
      dependenciaCategoria: dependenciaCategoria,
    );
  }

  factory ProductoCreadoPayload.fromJson(Map<String, Object?> json) {
    final product = _requiredMap(json['product'], 'product');
    final nombre = NombreProducto.fromInput(
      _requiredString(product['name'], 'product.name'),
    ).value;
    final categoriaId = _optionalNonEmptyString(
      product['category_id'],
      'product.category_id',
    );

    final variants = json['variants'];
    if (variants is! List || variants.length != 1) {
      throw const FormatException(
        'producto_creado sencillo requiere exactamente una variante.',
      );
    }
    final variant = ProductoCreadoVariante.fromJson(
      _requiredMap(variants.single, 'variants[0]'),
    );

    final dependencies = json['dependencies'];
    if (dependencies is! List) {
      throw const FormatException(
        'producto_creado requiere dependencies como arreglo.',
      );
    }
    if (dependencies.length > 1) {
      throw const FormatException(
        'El alta sencilla solo admite la dependencia de categoria.',
      );
    }
    final dependency = dependencies.isEmpty
        ? null
        : ProductoCreadoDependencia.fromJson(
            _requiredMap(dependencies.single, 'dependencies[0]'),
          );

    if ((categoriaId == null) != (dependency == null) ||
        dependency?.refId != categoriaId) {
      throw const FormatException(
        'La dependencia de categoria no coincide con product.category_id.',
      );
    }

    return ProductoCreadoPayload(
      nombre: nombre,
      categoriaId: categoriaId,
      variante: variant,
      dependenciaCategoria: dependency,
    );
  }

  Map<String, Object?> toJson() => {
    'product': {'name': nombre, 'category_id': categoriaId},
    'variants': [variante.toJson()],
    'dependencies': [
      if (dependenciaCategoria != null) dependenciaCategoria!.toJson(),
    ],
  };
}

class ProductoCreadoVariante {
  const ProductoCreadoVariante({
    required this.id,
    required this.precioVentaMenor,
  });

  final String id;
  final int precioVentaMenor;

  factory ProductoCreadoVariante.fromJson(Map<String, Object?> json) {
    if (json['name'] != null ||
        json['sku'] != null ||
        json['barcode'] != null) {
      throw const FormatException(
        'La variante sencilla no admite nombre, SKU ni codigo de barras.',
      );
    }
    if (json['is_default'] != true || _requiredInt(json['sort_order']) != 0) {
      throw const FormatException(
        'La variante sencilla debe ser predeterminada y usar sort_order 0.',
      );
    }
    final inventory = _requiredMap(
      json['inventory_configuration'],
      'variants[0].inventory_configuration',
    );
    if (inventory['behavior'] != 'none') {
      throw const FormatException(
        'El alta sencilla solo admite inventory behavior none.',
      );
    }

    return ProductoCreadoVariante(
      id: _requiredString(json['variant_id'], 'variants[0].variant_id'),
      precioVentaMenor: PrecioVenta.fromUnidadMenor(
        _requiredInt(json['sale_price_minor']),
      ).unidadMenor,
    );
  }

  Map<String, Object?> toJson() => {
    'variant_id': id,
    'name': null,
    'sku': null,
    'barcode': null,
    'sale_price_minor': precioVentaMenor,
    'is_default': true,
    'sort_order': 0,
    'inventory_configuration': {'behavior': 'none'},
  };
}

class ProductoCreadoDependencia {
  const ProductoCreadoDependencia({
    required this.refId,
    required this.baseEventId,
    required this.baseVersion,
    required this.baseServerSequence,
  });

  final String refId;
  final String? baseEventId;
  final int baseVersion;
  final int? baseServerSequence;

  factory ProductoCreadoDependencia.fromJson(Map<String, Object?> json) {
    if (json['ref_type'] != 'category') {
      throw const FormatException(
        'El alta sencilla solo admite dependencias category.',
      );
    }
    final baseEventId = _optionalNonEmptyString(
      json['base_event_id'],
      'dependencies[0].base_event_id',
    );
    final baseVersion = _requiredInt(json['base_version']);
    final baseServerSequence = _optionalNonNegativeInt(
      json['base_server_sequence'],
      'dependencies[0].base_server_sequence',
    );
    if (baseVersion < 1) {
      throw const FormatException(
        'dependencies[0].base_version debe ser >= 1.',
      );
    }
    if (baseEventId == null && baseServerSequence == null) {
      throw const FormatException(
        'La dependencia requiere base_event_id o base_server_sequence.',
      );
    }

    return ProductoCreadoDependencia(
      refId: _requiredString(json['ref_id'], 'dependencies[0].ref_id'),
      baseEventId: baseEventId,
      baseVersion: baseVersion,
      baseServerSequence: baseServerSequence,
    );
  }

  Map<String, Object?> toJson() => {
    'ref_type': 'category',
    'ref_id': refId,
    'base_event_id': baseEventId,
    'base_version': baseVersion,
    'base_server_sequence': baseServerSequence,
  };
}

Map<String, Object?> _requiredMap(Object? value, String fieldName) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('producto_creado requiere $fieldName como objeto.');
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('producto_creado requiere $fieldName.');
  }
  return value.trim();
}

String? _optionalNonEmptyString(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$fieldName debe ser string o null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Object? value) {
  final parsed = switch (value) {
    int() => value,
    num() when value == value.roundToDouble() => value.toInt(),
    _ => null,
  };
  if (parsed == null) {
    throw const FormatException('Se esperaba un entero en producto_creado.');
  }
  return parsed;
}

int? _optionalNonNegativeInt(Object? value, String fieldName) {
  if (value == null) return null;
  final parsed = _requiredInt(value);
  if (parsed < 0) {
    throw FormatException('$fieldName debe ser >= 0 o null.');
  }
  return parsed;
}
