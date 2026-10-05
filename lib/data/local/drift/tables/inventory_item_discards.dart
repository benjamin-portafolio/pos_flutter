import 'package:drift/drift.dart';

/// Prueba histórica de un descarte de recurso ya aplicado.
///
/// El contrato rev. 1 §7 exige que un descarte repetido sea idempotente **solo**
/// si existe evidencia persistida de que ese mismo descarte ya se aplicó, y que
/// esa evidencia impida que reaplicar el alta antigua del recurso lo resucite.
/// Por eso la fila sobrevive al `delete` del recurso que describe.
///
/// No usa `CommonFields` por la misma razón que `variant_inventory_memory`: es
/// una proyección derivada y reemplazable, cuya identidad es el recurso
/// descartado. No lleva `active` porque no se anula: si el identificador vuelve a
/// existir, es un recurso distinto con otro UUID y otra fila.
@DataClassName('InventoryItemDiscardRow')
class InventoryItemDiscards extends Table {
  /// Recurso descartado. **No** declara FK a propósito: la fila debe
  /// sobrevivir al borrado del recurso que certifica.
  TextColumn get inventoryItemId => text()();

  /// Evento `recurso_inventario_descartado` que aplicó el borrado. Es la prueba
  /// de idempotencia: si el recurso falta y este evento está registrado, el
  /// descarte ya ocurrió; si falta y no está, es un error, no un descarte válido.
  TextColumn get discardEventId => text()();

  /// Evento de producto que desvinculó la variante y habilitó el descarte.
  /// Permite comprobar que la fila corresponde al mismo disparador y no a otro.
  TextColumn get triggerProductEventId => text()();

  @override
  Set<Column> get primaryKey => {inventoryItemId};
}