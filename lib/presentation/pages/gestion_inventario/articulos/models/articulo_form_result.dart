import 'package:flutter/foundation.dart';

import '../../../../../domain/articulos/sale_configuration.dart';

@immutable
class ArticuloFormResult {
  const ArticuloFormResult({
    required this.nombre,
    required this.precioVenta,
    required this.categoriaId,
    required this.saleConfiguration,
  });

  final String nombre;
  final String precioVenta;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
}
