import 'package:flutter/material.dart';

import '../../../../domain/categorias/color_categoria.dart';

abstract final class CategoryColorPalette {
  static const selectableColors = <ColorCategoria>[
    ColorCategoria.amber,
    ColorCategoria.blue,
    ColorCategoria.blueGrey,
    ColorCategoria.brown,
    ColorCategoria.cyan,
    ColorCategoria.deepOrange,
    ColorCategoria.deepPurple,
    ColorCategoria.green,
    ColorCategoria.grey,
    ColorCategoria.indigo,
    ColorCategoria.lightBlue,
    ColorCategoria.lightGreen,
    ColorCategoria.lime,
    ColorCategoria.orange,
    ColorCategoria.pink,
    ColorCategoria.purple,
    ColorCategoria.red,
    ColorCategoria.teal,
    ColorCategoria.yellow,
  ];

  static Color resolve(ColorCategoria color) {
    return switch (color) {
      ColorCategoria.neutral => const Color(0xFF616161),
      ColorCategoria.amber => const Color(0xFFFFC107),
      ColorCategoria.blue => const Color(0xFF2196F3),
      ColorCategoria.blueGrey => const Color(0xFF607D8B),
      ColorCategoria.brown => const Color(0xFF795548),
      ColorCategoria.cyan => const Color(0xFF00BCD4),
      ColorCategoria.deepOrange => const Color(0xFFFF5722),
      ColorCategoria.deepPurple => const Color(0xFF673AB7),
      ColorCategoria.green => const Color(0xFF4CAF50),
      ColorCategoria.grey => const Color(0xFF9E9E9E),
      ColorCategoria.indigo => const Color(0xFF3F51B5),
      ColorCategoria.lightBlue => const Color(0xFF03A9F4),
      ColorCategoria.lightGreen => const Color(0xFF8BC34A),
      ColorCategoria.lime => const Color(0xFFCDDC39),
      ColorCategoria.orange => const Color(0xFFFF9800),
      ColorCategoria.pink => const Color(0xFFE91E63),
      ColorCategoria.purple => const Color(0xFF9C27B0),
      ColorCategoria.red => const Color(0xFFF44336),
      ColorCategoria.teal => const Color(0xFF009688),
      ColorCategoria.yellow => const Color(0xFFFFEB3B),
    };
  }
}
