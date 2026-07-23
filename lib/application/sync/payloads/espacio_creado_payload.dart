import '../../../domain/espacios/visibilidad_espacio.dart';

class EspacioCreadoPayload {
  const EspacioCreadoPayload({
    required this.nombre,
    required this.identificacion,
    required this.visibilidad,
  });

  static const aggregateType = 'espacio';
  static const eventType = 'espacio_creado';

  final String nombre;
  final String? identificacion;
  final VisibilidadEspacio visibilidad;

  factory EspacioCreadoPayload.fromJson(Map<String, Object?> json) {
    return EspacioCreadoPayload(
      nombre: _readRequiredName(json['nombre']),
      identificacion: _readOptionalIdentification(json['identificacion']),
      visibilidad: visibilidadEspacioFromEventValue(json['visibilidad']),
    );
  }

  Map<String, Object?> toJson() => {
    'nombre': nombre,
    'identificacion': identificacion,
    'visibilidad': visibilidad.eventValue,
  };

  static String _readRequiredName(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('espacio_creado requiere payload.nombre.');
    }
    return value.trim();
  }

  static String? _readOptionalIdentification(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException(
        'espacio_creado requiere payload.identificacion como texto o null.',
      );
    }

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
