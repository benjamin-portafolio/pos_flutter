/// Resultado comprobado tras el commit. La UI podrá informar descartes reales
/// y conservaciones que necesitan revisión, sin inferirlos del interruptor.
class ProductoInventoryUpdateResult {
  ProductoInventoryUpdateResult({
    List<String> discardedInventoryItemIds = const [],
    Map<String, String> preservationReasons = const {},
  }) : discardedInventoryItemIds = List.unmodifiable(discardedInventoryItemIds),
       preservationReasons = Map.unmodifiable(preservationReasons);
  final List<String> discardedInventoryItemIds;
  final Map<String, String> preservationReasons;
}
