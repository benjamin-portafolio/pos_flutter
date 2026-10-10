import '../../../../../domain/articulos/proveedor_variante.dart';
import 'proveedor_precio_input.dart';

/// Borrador de una selección. La relación original fija la política de fecha.
class ProveedorPrecioForm {
  const ProveedorPrecioForm({
    required this.proveedorId,
    required this.precio,
    required this.fecha,
    this.original,
  });

  factory ProveedorPrecioForm.fromRelacion(ProveedorVariante value) =>
      ProveedorPrecioForm(
        proveedorId: value.proveedorId,
        precio: ProveedorPrecioInput.format(value.precioInformadoMenor),
        fecha: dateFromMilliseconds(value.fechaInformadaMs),
        original: value,
      );

  final String proveedorId;
  final String precio;
  final DateTime? fecha;
  final ProveedorVariante? original;

  bool get conservaFecha {
    try {
      return original != null &&
          ProveedorPrecioInput.parse(precio).unidadMenor ==
              original!.precioInformadoMenor;
    } on FormatException {
      return false;
    }
  }

  ProveedorPrecioForm copyWith({String? precio, DateTime? fecha}) =>
      ProveedorPrecioForm(
        proveedorId: proveedorId,
        precio: precio ?? this.precio,
        fecha: fecha ?? this.fecha,
        original: original,
      );

  ProveedorVariante toRelacion() {
    final price = ProveedorPrecioInput.parse(precio);
    if (conservaFecha) return original!;
    if (fecha == null) {
      throw const FormatException('Selecciona la fecha informada.');
    }
    return ProveedorVariante(
      proveedorId: proveedorId,
      precioInformadoMenor: price.unidadMenor,
      fechaInformadaMs: fecha!.toUtc().millisecondsSinceEpoch,
    );
  }

  // El contrato admite instantes mayores que el rango de DateTime. Se pueden
  // consultar/conservar sin convertirlos; cambiar el precio exige elegir fecha.
  static DateTime? dateFromMilliseconds(int value) {
    if (value > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }

  static String formatDate(int milliseconds) {
    final date = dateFromMilliseconds(milliseconds);
    if (date == null) return 'UTC: $milliseconds ms';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
