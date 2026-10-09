import 'precio_proveedor.dart';

/// Relación vigente, independiente del precio de venta, costo y seguimiento.
class ProveedorVariante {
  ProveedorVariante({
    required String proveedorId,
    required int precioInformadoMenor,
    required int fechaInformadaMs,
  }) : proveedorId = _identity(proveedorId),
       precio = PrecioProveedor.fromUnidadMenor(precioInformadoMenor),
       fechaInformadaMs = _date(fechaInformadaMs);

  final String proveedorId;
  final PrecioProveedor precio;

  /// Instante UTC Unix. No se usa para resolver concurrencia.
  final int fechaInformadaMs;
  int get precioInformadoMenor => precio.unidadMenor;

  static String _identity(String value) {
    final id = value.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('El proveedor debe tener un UUID v4.');
    }
    return id;
  }

  static int _date(int value) {
    if (value < 1 || value > PrecioProveedor.maxUnidadMenor) {
      throw const FormatException('Fecha informada fuera del rango seguro.');
    }
    return value;
  }

  /// Copia inmutable y canónica; null significa que el consumidor no edita
  /// este campo. El conjunto vacío debe proporcionarse explícitamente.
  static List<ProveedorVariante>? canonical(List<ProveedorVariante>? values) {
    if (values == null) return null;
    final ids = <String>{};
    for (final value in values) {
      if (!ids.add(value.proveedorId)) {
        throw const FormatException('Proveedor repetido en la variante.');
      }
    }
    return List.unmodifiable(
      List<ProveedorVariante>.of(values)
        ..sort((a, b) => a.proveedorId.compareTo(b.proveedorId)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProveedorVariante &&
      proveedorId == other.proveedorId &&
      precioInformadoMenor == other.precioInformadoMenor &&
      fechaInformadaMs == other.fechaInformadaMs;

  @override
  int get hashCode =>
      Object.hash(proveedorId, precioInformadoMenor, fechaInformadaMs);
}
