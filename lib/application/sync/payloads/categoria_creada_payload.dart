import '../../../domain/categorias/color_categoria.dart';

class CategoriaCreadaPayload {
  const CategoriaCreadaPayload({
    required this.nombre,
    required this.color,
    required this.orden,
  });

  static const aggregateType = 'category';
  static const eventType = 'categoria_creada';

  final String nombre;
  final ColorCategoria color;
  final int? orden;

  factory CategoriaCreadaPayload.fromJson(Map<String, Object?> json) {
    return CategoriaCreadaPayload(
      nombre: _readRequiredName(json['name']),
      color: _readColor(json['color_key']),
      orden: _readOptionalOrder(json['sort_order']),
    );
  }

  Map<String, Object?> toJson() => {
    'name': nombre,
    'color_key': color.key,
    'sort_order': orden,
  };

  static String _readRequiredName(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('categoria_creada requiere payload.name.');
    }
    return value.trim();
  }

  static ColorCategoria _readColor(Object? value) {
    if (value is! String) {
      throw const FormatException(
        'categoria_creada requiere payload.color_key.',
      );
    }
    return ColorCategoria.fromKey(value);
  }

  static int? _readOptionalOrder(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw const FormatException(
      'categoria_creada requiere payload.sort_order entero o null.',
    );
  }
}
