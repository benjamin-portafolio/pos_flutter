/// Resultado del formulario de registro de ingreso/gasto adicional. La UI lo
/// envía al command service; `entryId` es la identidad estable de la intención
/// y `amountMinor` ya viene en centavos enteros (sin `double`).
class MovimientoFinancieroFormResult {
  const MovimientoFinancieroFormResult({
    required this.entryId,
    required this.categoryId,
    required this.amountMinor,
    required this.method,
    required this.occurredAtMs,
    this.notes,
    this.reference,
    this.affectsDrawer = false,
  });

  final bool affectsDrawer;
  final String entryId;
  final String categoryId;
  final int amountMinor;
  final String method;
  final int occurredAtMs;
  final String? notes;
  final String? reference;
}
