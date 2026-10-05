import 'variant_tracking_discard.dart';
export 'variant_tracking_discard.dart';
import 'variant_tracking_history.dart';
export 'variant_tracking_history.dart';
import 'variant_tracking_balance.dart';
export 'variant_tracking_balance.dart';
import 'variant_tracking_resource.dart';
export 'variant_tracking_resource.dart';
import '../models/sync_event.dart';

/// Lecturas de seguimiento de existencias para una variante.
///
/// Puerto que responde a las preguntas del contrato §3.1
/// (resolución del recurso) y §4 (elegibilidad del descarte). Vive en
/// `application` para que los command services no dependan de Drift ni de las
/// tablas concretas, y para que la presentación pueda consultar el recurso
/// actual o recuperable sin tocar la base directamente.
///
/// Ninguna de estas lecturas usa `event_refs` como evidencia: en `standalone`
/// esas filas no existen, y una comprobación que dependiera de ellas aprobaría
/// en un modo y rechazaría en el otro.
abstract interface class VariantInventoryTrackingStore {
  /// Recursos con procedencia explícita de la variante, en cualquier estado y
  /// sin filtro de actividad. Varios resultados son ambigüedad, no una lista de
  /// candidatos por orden de preferencia.
  Future<List<VariantTrackingResource>> resourcesByOriginVariant(
    String variantId,
  );

  Future<List<VariantTrackingResource>> selectionResources(String variantId);
  Future<VariantTrackingHistory> historyForVariant(String variantId);
  Future<VariantTrackingDiscard?> appliedDiscard(String inventoryItemId);
  Future<List<SyncEvent>> unappliedInventoryEvents();

  /// Variantes que mantienen vínculo directo con el recurso, incluidas las
  /// inactivas y las de otros artículos.
  Future<List<String>> directLinkedVariantIds(String inventoryItemId);

  /// Variantes que consumen el recurso como componente de receta, incluidas las
  /// inactivas.
  Future<List<String>> recipeUsingVariantIds(String inventoryItemId);

  /// Saldo materializado del recurso. `null` significa saldo ausente, que es
  /// inconsistencia y nunca autorización para descartar.
  Future<VariantTrackingBalance?> balanceOf(String inventoryItemId);

  /// Número de movimientos de cualquier tipo. El descarte exige cero, aunque la
  /// suma neta sea cero.
  Future<int> movementCount(String inventoryItemId);

  /// Identificadores de venta que capturaron el recurso en su configuración y que
  /// todavía esperan resolverse. Conserva el recurso mientras deba revisarse.
  Future<List<String>> unresolvedSaleIdsReferencing(String inventoryItemId);

  /// Comprobación de descarte ya aplicado y persistido. Un descarte repetido es
  /// idempotente solo con esta prueba; sin ella, un recurso faltante es error.
  Future<bool> hasAppliedDiscard(String inventoryItemId);

  /// Registra la prueba histórica del descarte para impedir que reaplicar un
  /// alta antigua resucite el recurso.
  Future<void> discardResource({
    required String inventoryItemId,
    required String discardEventId,
    required String triggerProductEventId,
  });
}
