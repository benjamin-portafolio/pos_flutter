import '../../../domain/articulos/nombre_producto.dart';
import '../../../domain/articulos/precio_venta.dart';
import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/articulos/sale_mode.dart';

class ProductoCreadoPayload {
  const ProductoCreadoPayload({
    required this.nombre,
    required this.categoriaId,
    required this.saleConfiguration,
    required this.variante,
    required this.dependenciaCategoria,
  });

  static const aggregateType = 'product';
  static const eventType = 'producto_creado';

  final String nombre;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
  final ProductoCreadoVariante variante;
  final ProductoCreadoDependencia? dependenciaCategoria;

  factory ProductoCreadoPayload.simple({
    required String nombre,
    required String? categoriaId,
    required String varianteId,
    required int precioVentaMenor,
    SaleConfiguration saleConfiguration = const UnitSaleConfiguration(),
    ProductoCreadoDependencia? dependenciaCategoria,
  }) {
    final normalizedName = NombreProducto.fromInput(nombre).value;
    final normalizedCategoryId = _optionalNonEmptyString(
      categoriaId,
      'product.category_id',
    );
    if (normalizedCategoryId == null && dependenciaCategoria != null) {
      throw const FormatException(
        'Un producto sin categoria no puede declarar dependencia de categoria.',
      );
    }
    if (dependenciaCategoria != null &&
        dependenciaCategoria.refId != normalizedCategoryId) {
      throw const FormatException(
        'La dependencia no coincide con product.category_id.',
      );
    }
    return ProductoCreadoPayload(
      nombre: normalizedName,
      categoriaId: normalizedCategoryId,
      saleConfiguration: saleConfiguration,
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
    final saleConfiguration = product.containsKey('sale_configuration')
        ? _parseSaleConfiguration(product['sale_configuration'])
        : const UnitSaleConfiguration();

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
    ProductoCreadoDependencia? categoryDependency;
    String? saleUnitDependencyId;
    for (var index = 0; index < dependencies.length; index++) {
      final dependency = _requiredMap(
        dependencies[index],
        'dependencies[$index]',
      );
      switch (dependency['ref_type']) {
        case 'category':
          if (categoryDependency != null) {
            throw const FormatException(
              'producto_creado no admite dependencias category duplicadas.',
            );
          }
          categoryDependency = _parseProductoCreadoDependencia(
            dependency,
            categoriaId: categoriaId,
            fieldName: 'dependencies[$index]',
          );
        case 'unit':
          if (saleUnitDependencyId != null) {
            throw const FormatException(
              'producto_creado no admite dependencias unit duplicadas.',
            );
          }
          if (dependency.keys.any(
            (key) => key != 'ref_type' && key != 'ref_id',
          )) {
            throw const FormatException(
              'La dependencia unit solo admite ref_type y ref_id.',
            );
          }
          saleUnitDependencyId = _requiredString(
            dependency['ref_id'],
            'dependencies[$index].ref_id',
          );
        default:
          throw const FormatException(
            'El alta sencilla solo admite dependencias category y unit.',
          );
      }
    }

    if (categoriaId == null && categoryDependency != null) {
      throw const FormatException(
        'La dependencia de categoria no coincide con product.category_id.',
      );
    }
    switch (saleConfiguration) {
      case UnitSaleConfiguration():
        if (saleUnitDependencyId != null) {
          throw const FormatException(
            'La venta por unidad no puede declarar dependencia unit.',
          );
        }
      case MeasuredSaleConfiguration():
        if (saleUnitDependencyId != saleConfiguration.saleUnitId) {
          throw const FormatException(
            'La dependencia unit no coincide con sale_unit_id.',
          );
        }
    }
    return ProductoCreadoPayload(
      nombre: nombre,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variante: variant,
      dependenciaCategoria: categoryDependency,
    );
  }

  Map<String, Object?> toJson() => {
    'product': {
      'name': nombre,
      'category_id': categoriaId,
      'sale_configuration': _saleConfigurationToJson(saleConfiguration),
    },
    'variants': [variante.toJson()],
    'dependencies': [
      if (dependenciaCategoria != null) dependenciaCategoria!.toJson(),
      if (saleConfiguration case final MeasuredSaleConfiguration measured)
        {'ref_type': 'unit', 'ref_id': measured.saleUnitId},
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
  };
}

class ProductoCreadoDependencia {
  const ProductoCreadoDependencia({
    required this.refId,
    required this.dependsOnEventId,
  });

  final String refId;
  final String dependsOnEventId;

  Map<String, Object?> toJson() => {
    'ref_type': 'category',
    'ref_id': refId,
    'depends_on_event_id': dependsOnEventId,
  };
}

SaleConfiguration _parseSaleConfiguration(Object? value) {
  final json = _requiredMap(value, 'product.sale_configuration');
  final modeValue = _requiredString(
    json['mode'],
    'product.sale_configuration.mode',
  );
  switch (modeValue) {
    case 'unit':
      if (json.containsKey('sale_unit_id') ||
          json.containsKey('price_reference_quantity_atomic')) {
        throw const FormatException(
          'La venta por unidad no admite campos medidos.',
        );
      }
      return const UnitSaleConfiguration();
    case 'measured':
      final reference = _requiredInt(json['price_reference_quantity_atomic']);
      if (reference <= 0) {
        throw const FormatException(
          'price_reference_quantity_atomic debe ser positivo.',
        );
      }
      return MeasuredSaleConfiguration(
        saleUnitId: _requiredString(
          json['sale_unit_id'],
          'product.sale_configuration.sale_unit_id',
        ),
        priceReferenceQuantityAtomic: reference,
      );
    default:
      throw FormatException('Modo de venta no soportado: $modeValue.');
  }
}

Map<String, Object?> _saleConfigurationToJson(
  SaleConfiguration configuration,
) => switch (configuration) {
  UnitSaleConfiguration() => {'mode': SaleMode.unit.code},
  MeasuredSaleConfiguration() => {
    'mode': SaleMode.measured.code,
    'sale_unit_id': configuration.saleUnitId,
    'price_reference_quantity_atomic':
        configuration.priceReferenceQuantityAtomic,
  },
};

ProductoCreadoDependencia? _parseProductoCreadoDependencia(
  Map<String, Object?> json, {
  required String? categoriaId,
  required String fieldName,
}) {
  final refId = _requiredString(json['ref_id'], '$fieldName.ref_id');
  if (refId != categoriaId) {
    throw const FormatException(
      'La dependencia de categoria no coincide con product.category_id.',
    );
  }

  if (json.containsKey('depends_on_event_id')) {
    return ProductoCreadoDependencia(
      refId: refId,
      dependsOnEventId: _requiredString(
        json['depends_on_event_id'],
        '$fieldName.depends_on_event_id',
      ),
    );
  }

  final baseEventId = _optionalNonEmptyString(
    json['base_event_id'],
    '$fieldName.base_event_id',
  );
  final baseVersion = _requiredInt(json['base_version']);
  final baseServerSequence = _optionalNonNegativeInt(
    json['base_server_sequence'],
    '$fieldName.base_server_sequence',
  );
  if (baseVersion < 1) {
    throw FormatException('$fieldName.base_version debe ser >= 1.');
  }
  if (baseEventId == null && baseServerSequence == null) {
    throw FormatException(
      '$fieldName requiere base_event_id o base_server_sequence.',
    );
  }
  if (baseEventId == null) return null;

  return ProductoCreadoDependencia(refId: refId, dependsOnEventId: baseEventId);
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
