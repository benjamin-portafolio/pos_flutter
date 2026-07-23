enum ColorCategoria {
  neutral('neutral'),
  amber('amber'),
  blue('blue'),
  blueGrey('blue_grey'),
  brown('brown'),
  cyan('cyan'),
  deepOrange('deep_orange'),
  deepPurple('deep_purple'),
  green('green'),
  grey('grey'),
  indigo('indigo'),
  lightBlue('light_blue'),
  lightGreen('light_green'),
  lime('lime'),
  orange('orange'),
  pink('pink'),
  purple('purple'),
  red('red'),
  teal('teal'),
  yellow('yellow');

  const ColorCategoria(this.key);

  final String key;

  static ColorCategoria fromKey(String key) {
    return ColorCategoria.values.firstWhere(
      (color) => color.key == key,
      orElse: () => throw FormatException(
        'La clave de color de categoría no es válida: $key',
      ),
    );
  }
}
