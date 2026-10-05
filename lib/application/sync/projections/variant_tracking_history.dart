import '../models/sync_event.dart';
import '../payloads/producto_creado_payload.dart';

/// Historia causal del producto y su proyección actual; no se ordena por reloj.
class VariantTrackingHistory {
  const VariantTrackingHistory({
    required this.variantExists,
    required this.createdEventId,
    required this.events,
    required this.currentState,
  });
  final bool variantExists;
  final String? createdEventId;
  final List<SyncEvent> events;
  final ProductoCreadoPayload? currentState;
}
