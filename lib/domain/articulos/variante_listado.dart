import '../inventario/recurso_inventario_listado.dart';

class VarianteListado {
  const VarianteListado({
    required this.varianteId,
    required this.nombre,
    required this.precioVentaMenor,
    this.costoEstandarMenor,
    required this.orden,
    this.inventario,
  });
  final String varianteId;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final int orden;

  /// Recurso y saldo de seguimiento directo; null si no controla existencias.
  final RecursoInventarioListado? inventario;
}
