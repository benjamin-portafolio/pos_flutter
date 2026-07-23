import 'package:flutter/foundation.dart';

import '../../../../../domain/categorias/color_categoria.dart';

@immutable
class CategoriaFormResult {
  const CategoriaFormResult({required this.nombre, required this.color});

  final String nombre;
  final ColorCategoria color;
}
