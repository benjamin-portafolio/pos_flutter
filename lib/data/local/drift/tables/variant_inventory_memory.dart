import 'package:drift/drift.dart';

import 'inventory_items.dart';
import 'product_variants.dart';

/// Último recurso de inventario directo conocido por una variante.
///
/// Proyección auxiliar derivada de los eventos de producto. Permite recuperar
/// la identidad, el saldo y el historial anteriores al reactivar el
/// seguimiento directo sin releer todo el historial en cada consulta.
///
/// No usa `CommonFields` porque cada fila es un dato derivado y reemplazable
/// del agregado producto/variante, sin ciclo de vida ni versión propios: su
/// identidad es la variante y la concurrencia la serializa el lock del producto
/// en `server_sync`. No lleva `active` porque una memoria no se anula; se
/// sustituye cuando aparece un vínculo directo nuevo o recuperado, y se elimina
/// cuando el recurso se descarta.
///
/// No reserva existencias: no participa del saldo, no habilita consumo y no se
/// usa para cobrar una venta. La configuración de venta capturada sigue siendo
/// la única fuente de consumo histórico.
///
/// Cascadas (contrato rev. 1 §5.2): borrar el recurso elimina **solo** su
/// memoria, nunca la variante; borrar la variante elimina **solo** su memoria,
/// nunca el recurso. No hay unicidad sobre `inventory_item_id` porque el índice
/// solo permite detectar memorias de otras variantes (condición 6 de
/// elegibilidad de descarte).
@DataClassName('VariantInventoryMemoryRow')
@TableIndex.sql(
  'CREATE INDEX ix_variant_inventory_memory_item ON variant_inventory_memory (inventory_item_id)',
)
class VariantInventoryMemory extends Table {
  /// Variante que recuerda el recurso. La cascada retira su memoria sin
  /// tocar los recursos de inventario.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// Último recurso directo conocido de la variante. La cascada retira la
  /// memoria cuando el recurso se descarta.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.cascade)();

  /// Evento de producto cuya configuración acreditó esta memoria: el que
  /// estableció el vínculo o el que lo quitó conservando el recurso.
  ///
  /// No es una FK al historial de eventos: `events` se conserva por otros
  /// caminos y esta fila debe poder reconstruirse cuando la evidencia local no
  /// está disponible (ver migración PostgreSQL y reconstrucción legada).
  TextColumn get sourceEventId => text()();

  /// Secuencia oficial del evento acreditado. Null mientras el estado es solo
  /// local; permite reconocer un eco sin sobrescribir una memoria posterior.
  IntColumn get sourceServerSequence => integer().nullable()();

  @override
  Set<Column> get primaryKey => {variantId};
}
