enum ColorCategoria {
  neutral('neutral'),
  red('red'),
  orange('orange'),
  amber('amber'),
  green('green'),
  teal('teal'),
  blue('blue'),
  indigo('indigo'),
  purple('purple'),
  pink('pink');

  const ColorCategoria(this.key);

  final String key;

  static ColorCategoria fromKey(String key) {
    return ColorCategoria.values.firstWhere(
      (color) => color.key == key,
      orElse: () => throw FormatException(
        'La clave de color de categoria no es valida: $key',
      ),
    );
  }
}
