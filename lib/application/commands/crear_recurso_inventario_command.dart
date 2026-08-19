class CrearRecursoInventarioCommand {
  const CrearRecursoInventarioCommand({
    required this.nombre,
    required this.defaultUnitId,
    this.quantityDeltaAtomic,
    this.movementReason,
  });

  final String nombre;
  final String defaultUnitId;
  final int? quantityDeltaAtomic;
  final String? movementReason;
}
