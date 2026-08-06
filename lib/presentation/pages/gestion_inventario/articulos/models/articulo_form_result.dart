import 'package:flutter/foundation.dart';

@immutable
class ArticuloFormResult {
  const ArticuloFormResult({
    required this.nombre,
    required this.precioVenta,
    required this.categoriaId,
  });

  final String nombre;
  final String precioVenta;
  final String? categoriaId;
}
