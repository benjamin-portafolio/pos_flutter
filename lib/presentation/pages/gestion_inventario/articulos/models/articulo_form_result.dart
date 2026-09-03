import 'package:flutter/foundation.dart';

import '../../../../../domain/articulos/sale_configuration.dart';
import 'recipe_component_form_result.dart';

@immutable
class ArticuloFormResult {
  const ArticuloFormResult({
    required this.nombre,
    required this.variantes,
    required this.categoriaId,
    required this.saleConfiguration,
  });

  final String nombre;
  final List<ArticuloFormVarianteResult> variantes;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
}

@immutable
class ArticuloFormVarianteResult {
  const ArticuloFormVarianteResult({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.inventoryUnitId,
    this.existenciaInicial,
    this.recipeComponents = const [],
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;
  final String? inventoryUnitId;
  final String? existenciaInicial;
  final List<RecipeComponentFormResult> recipeComponents;

  bool get seguimientoExistencias => inventoryUnitId != null;
  bool get usaReceta => recipeComponents.isNotEmpty;

  ArticuloFormVarianteResult copyWith({
    String? nombre,
    bool clearNombre = false,
    String? precioVenta,
    String? costoEstandar,
    bool clearCostoEstandar = false,
    String? inventoryUnitId,
    bool clearInventoryUnitId = false,
    String? existenciaInicial,
    bool clearExistenciaInicial = false,
    List<RecipeComponentFormResult>? recipeComponents,
    bool clearRecipeComponents = false,
  }) {
    return ArticuloFormVarianteResult(
      nombre: clearNombre ? null : nombre ?? this.nombre,
      precioVenta: precioVenta ?? this.precioVenta,
      costoEstandar: clearCostoEstandar
          ? null
          : costoEstandar ?? this.costoEstandar,
      inventoryUnitId: clearInventoryUnitId
          ? null
          : inventoryUnitId ?? this.inventoryUnitId,
      existenciaInicial: clearExistenciaInicial
          ? null
          : existenciaInicial ?? this.existenciaInicial,
      recipeComponents: clearRecipeComponents
          ? const []
          : recipeComponents ?? this.recipeComponents,
    );
  }
}
