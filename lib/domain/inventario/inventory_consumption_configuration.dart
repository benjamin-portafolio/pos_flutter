import 'dart:convert';

/// Configuración de consumo congelada en una captura de venta. Conserva el
/// formato legado [vínculo directo, [recurso, cantidad], ...], sin mirar el
/// catálogo actual ni emplear búsquedas de texto sobre JSON.
class InventoryConsumptionConfiguration {
  const InventoryConsumptionConfiguration({
    required this.directItemId,
    required this.components,
  });
  final String? directItemId;
  final List<({String itemId, int quantityAtomic})> components;

  Set<String> get inventoryItemIds => {
    ?directItemId,
    ...components.map((c) => c.itemId),
  };

  factory InventoryConsumptionConfiguration.fromKey(String key) {
    final value = jsonDecode(key);
    if (value is! List ||
        value.isEmpty ||
        (value.first != null && value.first is! String)) {
      throw const FormatException(
        'Configuración capturada de inventario inválida.',
      );
    }
    final components = <({String itemId, int quantityAtomic})>[];
    for (final row in value.skip(1)) {
      if (row is! List ||
          row.length != 2 ||
          row[0] is! String ||
          row[1] is! int ||
          (row[1] as int) <= 0) {
        throw const FormatException(
          'Componente de consumo capturado inválido.',
        );
      }
      components.add((itemId: row[0] as String, quantityAtomic: row[1] as int));
    }
    return InventoryConsumptionConfiguration(
      directItemId: value.first as String?,
      components: components,
    );
  }

  String toKey() => jsonEncode([
    directItemId,
    for (final c in components) [c.itemId, c.quantityAtomic],
  ]);
}
