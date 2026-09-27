/// Intención de registrar un ingreso/gasto adicional. `entryId` es la
/// identidad estable de la captura: reintentar el mismo guardado reutiliza
/// esta id y la fecha efectiva (`occurredAtMs`) que capturó el formulario.
class RegistrarMovimientoFinancieroCommand {
  const RegistrarMovimientoFinancieroCommand({
    required this.entryId,
    required this.categoryId,
    required this.amountMinor,
    required this.method,
    required this.occurredAtMs,
    this.notes,
    this.reference,
    this.affectsDrawer = false,
  });

  /// Selección explícita de entrada/salida del cajón de esta terminal.
  final bool affectsDrawer;
  final String entryId;
  final String categoryId;

  /// Importe en centavos (entero positivo, entero seguro).
  final int amountMinor;

  /// Medio `cash` | `transfer`.
  final String method;

  /// Instante efectivo UTC en ms; el command rechaza futuro (> now + 5 min).
  final int occurredAtMs;
  final String? notes;
  final String? reference;
}
