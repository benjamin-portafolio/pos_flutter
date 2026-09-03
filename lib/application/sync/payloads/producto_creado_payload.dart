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
    required this.dependenciasInventario,
  });

  static const aggregateType = 'product';
  static const eventType = 'producto_creado';

  final String nombre;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
  final List<ProductoCreadoVariante> variantes;
  final ProductoCreadoDependencia? dependenciaCategoria;
  final List<ProductoCreadoInventarioDependencia> dependenciasInventario;

  factory ProductoCreadoPayload.create({
    required String nombre,
    required String? categoriaId,
    required SaleConfiguration saleConfiguration,
    required List<ProductoCreadoVariante> variantes,
    ProductoCreadoDependencia? dependenciaCategoria,
    List<ProductoCreadoInventarioDependencia> dependenciasInventario = const [],
  }) {
    final normalizedName = NombreProducto.fromInput(nombre).value;
    final normalizedCategoryId = _optionalNonEmptyString(
      categoriaId,
      'product.category_id',
    );
    _validateCategoryDependency(normalizedCategoryId, dependenciaCategoria);
    final validatedVariants = _validateVariants(variantes);
    final validatedInventoryDependencies = _validateInventoryDependencies(
      validatedVariants,
      dependenciasInventario,
    );
    return ProductoCreadoPayload._(
      nombre: normalizedName,
      categoriaId: normalizedCategoryId,
      saleConfiguration: saleConfiguration,
      variantes: validatedVariants,
      dependenciaCategoria: dependenciaCategoria,
      dependenciasInventario: validatedInventoryDependencies,
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
      dependenciasInventario: const [],
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
    final inventoryDependencies = <ProductoCreadoInventarioDependencia>[];
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
        case 'inventory_item':
          inventoryDependencies.add(
            ProductoCreadoInventarioDependencia.fromJson(
              dependency,
              fieldName: 'dependencies[$index]',
            ),
          );
        default:
          throw const FormatException(
            'producto_creado solo admite dependencias category, unit e inventory_item.',
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

    final validatedVariants = _validateVariants(variantes);
    return ProductoCreadoPayload._(
      nombre: nombre,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variantes: validatedVariants,
      dependenciaCategoria: categoryDependency,
      dependenciasInventario: _validateInventoryDependencies(
        validatedVariants,
        inventoryDependencies,
      ),
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
      ...dependenciasInventario.map((dependency) => dependency.toJson()),
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
    required this.inventoryItemId,
    required this.componentesReceta,
    required this.esPredeterminada,
    required this.orden,
  });

  factory ProductoCreadoVariante.create({
    required String id,
    required String? nombre,
    required int precioVentaMenor,
    required int? costoEstandarMenor,
    String? inventoryItemId,
    List<ProductoCreadoComponenteReceta> componentesReceta = const [],
    required bool esPredeterminada,
    required int orden,
  }) {
    final normalizedName = NombreVariante.fromInput(nombre);
    final validatedComponents = _validateRecipeComponents(componentesReceta);
    final normalizedInventoryItemId = _optionalUuidV4(
      inventoryItemId,
      'inventory_item_id',
    );
    if (normalizedInventoryItemId != null && validatedComponents.isNotEmpty) {
      throw const FormatException(
        'Una variante no puede usar vínculo directo y receta simultáneamente.',
      );
    }
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
      inventoryItemId: normalizedInventoryItemId,
      componentesReceta: validatedComponents,
      esPredeterminada: esPredeterminada,
      orden: orden,
    );
  }

  final String id;
  final String? nombre;
  final String? nameKey;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final String? inventoryItemId;
  final List<ProductoCreadoComponenteReceta> componentesReceta;
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
    final recipeComponents = _parseRecipeComponents(
      json['inventory_configuration'],
      fieldName: '$fieldName.inventory_configuration',
    );
    try {
      return ProductoCreadoVariante.create(
        id: _requiredString(json['variant_id'], '$fieldName.variant_id'),
        nombre: rawName as String?,
        precioVentaMenor: _requiredInt(
          json['sale_price_minor'],
          '$fieldName.sale_price_minor',
        ),
        costoEstandarMenor: parsedCost,
        inventoryItemId: _optionalNonEmptyString(
          json['inventory_item_id'],
          '$fieldName.inventory_item_id',
        ),
        componentesReceta: recipeComponents,
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
    if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
    if (componentesReceta.isNotEmpty)
      'inventory_configuration': {
        'enabled': true,
        'components': componentesReceta
            .map((component) => component.toJson())
            .toList(growable: false),
      },
    'is_default': esPredeterminada,
    'sort_order': orden,
  };
}

class ProductoCreadoComponenteReceta {
  const ProductoCreadoComponenteReceta._({
    required this.inventoryItemId,
    required this.quantityAtomic,
  });

  factory ProductoCreadoComponenteReceta.create({
    required String inventoryItemId,
    required int quantityAtomic,
  }) {
    if (quantityAtomic <= 0 || quantityAtomic > 9007199254740991) {
      throw const FormatException(
        'quantity_atomic debe ser positivo y estar dentro del rango seguro.',
      );
    }
    return ProductoCreadoComponenteReceta._(
      inventoryItemId: _requiredUuidV4(
        inventoryItemId,
        'recipe_component.inventory_item_id',
      ),
      quantityAtomic: quantityAtomic,
    );
  }

  factory ProductoCreadoComponenteReceta.fromJson(
    Map<String, Object?> json, {
    required String fieldName,
  }) {
    if (json.keys.any(
      (key) => key != 'inventory_item_id' && key != 'quantity_atomic',
    )) {
      throw FormatException(
        '$fieldName solo admite inventory_item_id y quantity_atomic.',
      );
    }
    return ProductoCreadoComponenteReceta.create(
      inventoryItemId: _requiredString(
        json['inventory_item_id'],
        '$fieldName.inventory_item_id',
      ),
      quantityAtomic: _requiredInt(
        json['quantity_atomic'],
        '$fieldName.quantity_atomic',
      ),
    );
  }

  final String inventoryItemId;
  final int quantityAtomic;

  Map<String, Object?> toJson() => {
    'inventory_item_id': inventoryItemId,
    'quantity_atomic': quantityAtomic,
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

class ProductoCreadoInventarioDependencia {
  const ProductoCreadoInventarioDependencia({
    required this.refId,
    this.dependsOnEventId,
  });

  final String refId;
  final String? dependsOnEventId;

  factory ProductoCreadoInventarioDependencia.fromJson(
    Map<String, Object?> json, {
    required String fieldName,
  }) {
    if (json.keys.any(
      (key) =>
          key != 'ref_type' && key != 'ref_id' && key != 'depends_on_event_id',
    )) {
      throw FormatException(
        '$fieldName solo admite ref_type, ref_id y depends_on_event_id.',
      );
    }
    return ProductoCreadoInventarioDependencia(
      refId: _requiredUuidV4(
        _requiredString(json['ref_id'], '$fieldName.ref_id'),
        '$fieldName.ref_id',
      ),
      dependsOnEventId: _optionalUuidV4(
        _optionalNonEmptyString(
          json['depends_on_event_id'],
          '$fieldName.depends_on_event_id',
        ),
        '$fieldName.depends_on_event_id',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'ref_type': 'inventory_item',
    'ref_id': refId,
    if (dependsOnEventId != null) 'depends_on_event_id': dependsOnEventId,
  };
}

List<ProductoCreadoComponenteReceta> _parseRecipeComponents(
  Object? value, {
  required String fieldName,
}) {
  if (value == null) return const [];
  final configuration = _requiredMap(value, fieldName);
  final enabled = configuration['enabled'];
  if (enabled is! bool) {
    throw FormatException('$fieldName.enabled debe ser booleano.');
  }
  final rawComponents = configuration['components'];
  if (!enabled) {
    if (rawComponents != null) {
      throw FormatException(
        '$fieldName deshabilitada no puede declarar componentes.',
      );
    }
    return const [];
  }
  if (rawComponents is! List || rawComponents.isEmpty) {
    throw FormatException(
      '$fieldName habilitada como receta requiere componentes.',
    );
  }
  return _validateRecipeComponents([
    for (var index = 0; index < rawComponents.length; index++)
      ProductoCreadoComponenteReceta.fromJson(
        _requiredMap(rawComponents[index], '$fieldName.components[$index]'),
        fieldName: '$fieldName.components[$index]',
      ),
  ]);
}

List<ProductoCreadoComponenteReceta> _validateRecipeComponents(
  List<ProductoCreadoComponenteReceta> components,
) {
  final ids = <String>{};
  for (final component in components) {
    if (!ids.add(component.inventoryItemId)) {
      throw const FormatException(
        'Un recurso de inventario no puede repetirse en la misma receta.',
      );
    }
  }
  final sorted = List<ProductoCreadoComponenteReceta>.of(components)
    ..sort(
      (left, right) => left.inventoryItemId.compareTo(right.inventoryItemId),
    );
  return List.unmodifiable(sorted);
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
  final inventoryItemIds = <String>{};
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
    final inventoryItemId = variant.inventoryItemId;
    if (inventoryItemId != null && !inventoryItemIds.add(inventoryItemId)) {
      throw const FormatException(
        'Un recurso de inventario solo puede vincularse directamente con una variante.',
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

List<ProductoCreadoInventarioDependencia> _validateInventoryDependencies(
  List<ProductoCreadoVariante> variants,
  List<ProductoCreadoInventarioDependencia> dependencies,
) {
  final expectedIds = variants
      .expand(
        (variant) => [
          if (variant.inventoryItemId != null) variant.inventoryItemId!,
          ...variant.componentesReceta.map(
            (component) => component.inventoryItemId,
          ),
        ],
      )
      .toSet();
  final actualIds = <String>{};
  for (final dependency in dependencies) {
    if (!actualIds.add(dependency.refId)) {
      throw const FormatException(
        'producto_creado no admite dependencias inventory_item duplicadas.',
      );
    }
  }
  if (expectedIds.length != actualIds.length ||
      !expectedIds.containsAll(actualIds)) {
    throw const FormatException(
      'Las dependencias inventory_item deben coincidir con los vínculos directos y componentes de receta.',
    );
  }
  return List.unmodifiable(dependencies);
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

String? _optionalUuidV4(String? value, String fieldName) {
  if (value == null) return null;
  return _requiredUuidV4(value, fieldName);
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
