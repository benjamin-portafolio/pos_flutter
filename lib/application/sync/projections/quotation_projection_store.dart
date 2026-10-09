import '../models/sync_event.dart';
import 'quotation_projection.dart';
import 'quotation_item_projection.dart';

abstract interface class QuotationProjectionStore {
  /// Mismo límite SQLite que borrador, evento y refs.
  Future<T> atomic<T>(Future<T> Function() action);
  Future<QuotationProjection?> findById(String id);
  Future<QuotationProjection?> findByCurrentSaleId(String saleId);
  Future<SyncEvent?> findEventById(String eventId);
  Future<List<QuotationItemProjection>> items(String quotationId);

  /// Inserciones estrictas; guardar nunca sobrescribe un documento emitido.
  Future<void> insertQuotation(QuotationProjection quotation);
  Future<void> insertItem(QuotationItemProjection item);

  /// Comprueba colisiones globales antes de crear eventos de borrador.
  Future<bool> containsSaleItem(String id);

  /// Sólo avanza el vínculo y metadatos; no modifica el documento emitido.
  Future<void> linkRecoveredSale({
    required String quotationId,
    required int baseVersion,
    required String baseEventId,
    required String? previousSaleId,
    required String saleId,
    required String eventId,
  });
}
