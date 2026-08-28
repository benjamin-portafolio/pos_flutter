import 'package:flutter/foundation.dart';

import '../../../../../domain/articulos/sale_configuration.dart';

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
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;
  final String? inventoryUnitId;
  final String? existenciaInicial;

  bool get seguimientoExistencias => inventoryUnitId != null;

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
    );
  }
}
