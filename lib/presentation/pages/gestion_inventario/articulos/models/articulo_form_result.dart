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
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;

  ArticuloFormVarianteResult copyWith({
    String? nombre,
    bool clearNombre = false,
    String? precioVenta,
    String? costoEstandar,
    bool clearCostoEstandar = false,
  }) {
    return ArticuloFormVarianteResult(
      nombre: clearNombre ? null : nombre ?? this.nombre,
      precioVenta: precioVenta ?? this.precioVenta,
      costoEstandar: clearCostoEstandar
          ? null
          : costoEstandar ?? this.costoEstandar,
    );
  }
}
