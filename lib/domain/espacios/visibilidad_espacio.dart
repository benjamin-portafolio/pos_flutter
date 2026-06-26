enum VisibilidadEspacio { sinRestriccion, soloRestringido }

extension VisibilidadEspacioEventValue on VisibilidadEspacio {
  String get eventValue {
    return switch (this) {
      VisibilidadEspacio.sinRestriccion => 'sin_restriccion',
      VisibilidadEspacio.soloRestringido => 'solo_restringido',
    };
  }
}

VisibilidadEspacio visibilidadEspacioFromEventValue(Object? value) {
  if (value is String) {
    return switch (value) {
      'sin_restriccion' => VisibilidadEspacio.sinRestriccion,
      'solo_restringido' => VisibilidadEspacio.soloRestringido,
      _ => throw FormatException('Visibilidad de espacio desconocida: $value'),
    };
  }

  if (value is int) {
    return switch (value) {
      0 => VisibilidadEspacio.sinRestriccion,
      1 => VisibilidadEspacio.soloRestringido,
      _ => throw FormatException(
        'Indice legado de visibilidad de espacio desconocido: $value',
      ),
    };
  }

  throw FormatException('Visibilidad de espacio invalida: $value');
}
