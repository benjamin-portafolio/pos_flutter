import '../../../domain/articulos/costo_estandar.dart';
import '../../../domain/articulos/nombre_producto.dart';
import '../../../domain/articulos/nombre_variante.dart';
import '../../../domain/articulos/precio_venta.dart';
import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/articulos/sale_mode.dart';

class ProductoCreadoPayload {
  const ProductoCreadoPayload._({
    required this.nombre,
    required this.categoriaId,
    required this.saleConfiguration,
    required this.variantes,
    required this.dependenciaCategoria,
  });

  static const aggregateType = 'product';
  static const eventType = 'producto_creado';

  final String nombre;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
  final List<ProductoCreadoVariante> variantes;
  final ProductoCreadoDependencia? dependenciaCategoria;

  factory ProductoCreadoPayload.create({
    required String nombre,
    required String? categoriaId,
    required SaleConfiguration saleConfiguration,
    required List<ProductoCreadoVariante> variantes,
    ProductoCreadoDependencia? dependenciaCategoria,
  }) {
    final normalizedName = NombreProducto.fromInput(nombre).value;
    final normalizedCategoryId = _optionalNonEmptyString(
      categoriaId,
      'product.category_id',
    );
    _validateCategoryDependency(normalizedCategoryId, dependenciaCategoria);
    return ProductoCreadoPayload._(
      nombre: normalizedName,
      categoriaId: normalizedCategoryId,
      saleConfiguration: saleConfiguration,
      variantes: _validateVariants(variantes),
      dependenciaCategoria: dependenciaCategoria,
    );
  }

  factory ProductoCreadoPayload.simple({
    required String nombre,
    required String? categoriaId,
    required String varianteId,
    required int precioVentaMenor,
    SaleConfiguration saleConfiguration = const UnitSaleConfiguration(),
    ProductoCreadoDependencia? dependenciaCategoria,
  }) {
    return ProductoCreadoPayload.create(
      nombre: nombre,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variantes: [
        ProductoCreadoVariante.create(
          id: varianteId,
          nombre: null,
          precioVentaMenor: precioVentaMenor,
          costoEstandarMenor: null,
          esPredeterminada: true,
          orden: 0,
        ),
      ],
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

    final variantsJson = json['variants'];
    if (variantsJson is! List || variantsJson.isEmpty) {
      throw const FormatException(
        'producto_creado requiere una o más variantes.',
      );
    }
    final variantes = <ProductoCreadoVariante>[];
    for (var index = 0; index < variantsJson.length; index++) {
      variantes.add(
        ProductoCreadoVariante.fromJson(
          _requiredMap(variantsJson[index], 'variants[$index]'),
          fieldName: 'variants[$index]',
        ),
      );
    }

    final dependencies = json['dependencies'];
    if (dependencies is! List) {
      throw const FormatException(
        'producto_creado requiere dependencies como arreglo.',
      );
    }
    ProductoCreadoDependencia? categoryDependency;
    var categoryDependencySeen = false;
    String? saleUnitDependencyId;
    for (var index = 0; index < dependencies.length; index++) {
      final dependency = _requiredMap(
        dependencies[index],
        'dependencies[$index]',
      );
      switch (dependency['ref_type']) {
        case 'category':
          if (categoryDependencySeen) {
            throw const FormatException(
              'producto_creado no admite dependencias category duplicadas.',
            );
          }
          categoryDependencySeen = true;
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
            'producto_creado solo admite dependencias category y unit.',
          );
      }
    }

    if (categoriaId == null && categoryDependencySeen) {
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

    return ProductoCreadoPayload._(
      nombre: nombre,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variantes: _validateVariants(variantes),
      dependenciaCategoria: categoryDependency,
    );
  }

  Map<String, Object?> toJson() => {
    'product': {
      'name': nombre,
      'category_id': categoriaId,
      'sale_configuration': _saleConfigurationToJson(saleConfiguration),
    },
    'variants': variantes.map((variant) => variant.toJson()).toList(),
    'dependencies': [
      if (dependenciaCategoria != null) dependenciaCategoria!.toJson(),
      if (saleConfiguration case final MeasuredSaleConfiguration measured)
        {'ref_type': 'unit', 'ref_id': measured.saleUnitId},
    ],
  };
}

class ProductoCreadoVariante {
  const ProductoCreadoVariante._({
    required this.id,
    required this.nombre,
    required this.nameKey,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
    required this.esPredeterminada,
    required this.orden,
  });

  factory ProductoCreadoVariante.create({
    required String id,
    required String? nombre,
    required int precioVentaMenor,
    required int? costoEstandarMenor,
    required bool esPredeterminada,
    required int orden,
  }) {
    final normalizedName = NombreVariante.fromInput(nombre);
    return ProductoCreadoVariante._(
      id: _requiredUuidV4(id, 'variant_id'),
      nombre: normalizedName.value,
      nameKey: normalizedName.nameKey,
      precioVentaMenor: PrecioVenta.fromUnidadMenor(
        precioVentaMenor,
      ).unidadMenor,
      costoEstandarMenor: costoEstandarMenor == null
          ? null
          : CostoEstandar.fromUnidadMenor(costoEstandarMenor).unidadMenor,
      esPredeterminada: esPredeterminada,
      orden: orden,
    );
  }

  final String id;
  final String? nombre;
  final String? nameKey;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final bool esPredeterminada;
  final int orden;

  factory ProductoCreadoVariante.fromJson(
    Map<String, Object?> json, {
    required String fieldName,
  }) {
    if (json['sku'] != null || json['barcode'] != null) {
      throw FormatException('$fieldName no admite SKU ni código de barras.');
    }
    final rawName = json['name'];
    if (rawName != null && rawName is! String) {
      throw FormatException('$fieldName.name debe ser string o null.');
    }
    final standardCost = json.containsKey('standard_cost_minor')
        ? json['standard_cost_minor']
        : null;
    final parsedCost = standardCost == null
        ? null
        : _requiredInt(standardCost, '$fieldName.standard_cost_minor');
    final isDefault = json['is_default'];
    if (isDefault is! bool) {
      throw FormatException('$fieldName.is_default debe ser booleano.');
    }
    try {
      return ProductoCreadoVariante.create(
        id: _requiredString(json['variant_id'], '$fieldName.variant_id'),
        nombre: rawName as String?,
        precioVentaMenor: _requiredInt(
          json['sale_price_minor'],
          '$fieldName.sale_price_minor',
        ),
        costoEstandarMenor: parsedCost,
        esPredeterminada: isDefault,
        orden: _requiredInt(json['sort_order'], '$fieldName.sort_order'),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        error.message?.toString() ?? '$fieldName inválida.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'variant_id': id,
    'name': nombre,
    'sku': null,
    'barcode': null,
    'sale_price_minor': precioVentaMenor,
    'standard_cost_minor': costoEstandarMenor,
    'is_default': esPredeterminada,
    'sort_order': orden,
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

List<ProductoCreadoVariante> _validateVariants(
  List<ProductoCreadoVariante> variants,
) {
  if (variants.isEmpty) {
    throw const FormatException(
      'producto_creado requiere una o más variantes.',
    );
  }
  final ids = <String>{};
  final nameKeys = <String>{};
  var defaults = 0;
  for (var index = 0; index < variants.length; index++) {
    final variant = variants[index];
    if (!ids.add(variant.id)) {
      throw const FormatException('Los IDs de variantes no pueden repetirse.');
    }
    final nameKey = variant.nameKey;
    if (nameKey != null && !nameKeys.add(nameKey)) {
      throw const FormatException(
        'Los nombres de variantes no pueden repetirse.',
      );
    }
    if (variant.orden != index) {
      throw const FormatException(
        'sort_order debe ser consecutivo desde cero.',
      );
    }
    if (variant.esPredeterminada) defaults++;
    if (variant.esPredeterminada != (index == 0)) {
      throw const FormatException(
        'La primera variante debe ser la única predeterminada.',
      );
    }
  }
  if (defaults != 1) {
    throw const FormatException(
      'producto_creado requiere exactamente una variante predeterminada.',
    );
  }
  return List.unmodifiable(variants);
}

void _validateCategoryDependency(
  String? categoryId,
  ProductoCreadoDependencia? dependency,
) {
  if (categoryId == null && dependency != null) {
    throw const FormatException(
      'Un producto sin categoria no puede declarar dependencia de categoria.',
    );
  }
  if (dependency != null && dependency.refId != categoryId) {
    throw const FormatException(
      'La dependencia no coincide con product.category_id.',
    );
  }
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
      final reference = _requiredInt(
        json['price_reference_quantity_atomic'],
        'product.sale_configuration.price_reference_quantity_atomic',
      );
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
  final baseVersion = _requiredInt(
    json['base_version'],
    '$fieldName.base_version',
  );
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

String _requiredUuidV4(String value, String fieldName) {
  final normalized = _requiredString(value, fieldName);
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    throw FormatException('$fieldName debe ser un UUID v4.');
  }
  return normalized;
}

String? _optionalNonEmptyString(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$fieldName debe ser string o null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Object? value, String fieldName) {
  final parsed = switch (value) {
    int() => value,
    num() when value == value.roundToDouble() => value.toInt(),
    _ => null,
  };
  if (parsed == null) {
    throw FormatException('$fieldName debe ser un entero.');
  }
  return parsed;
}

int? _optionalNonNegativeInt(Object? value, String fieldName) {
  if (value == null) return null;
  final parsed = _requiredInt(value, fieldName);
  if (parsed < 0) {
    throw FormatException('$fieldName debe ser >= 0 o null.');
  }
  return parsed;
}
