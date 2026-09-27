import 'package:uuid/uuid.dart';

import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/categoria_financiera_creada_payload.dart';
import '../../sync/projections/financial_category_projection_store.dart';
import '../local_command_context.dart';
import 'crear_categoria_financiera_command.dart';

/// Comando de alta de categoría financiera. Normaliza entradas vía el payload
/// (NFKC+trim y mensajes canónicos), usa la identidad estable del command para
/// idempotencia (`aggregate_id`) y persiste evento+refs+proyección como una
/// sola transacción atómica. Devuelve el `event_id` creado (o el previo en un
/// reintento idéntico) para que el flujo registre movimientos de inmediato.
class CategoriaFinancieraCommandService {
  CategoriaFinancieraCommandService({
    required this.store,
    required this.events,
    required this.context,
  });

  final FinancialCategoryProjectionStore store;
  final LocalEventStore events;
  final LocalCommandContext context;

  Future<String> crear(CrearCategoriaFinancieraCommand command) =>
      store.atomic(() async {
        final payload = CategoriaFinancieraCreadaPayload.fromJson({
          'name': command.name,
          'direction': command.direction.code,
          'nature': command.nature.code,
        });
        final previous = await store.categoryEvent(command.categoryId);
        if (previous != null) {
          final p = CategoriaFinancieraCreadaPayload.fromJson(previous.payload);
          if (p.name != payload.name ||
              p.direction != payload.direction ||
              p.nature != payload.nature) {
            throw StateError('Esta categoría ya se creó con otros datos.');
          }
          return previous.eventId;
        }
        final refs = payload.refs(command.categoryId);
        if (context.userId.trim().isEmpty ||
            context.deviceId.trim().isEmpty ||
            refs.any((r) => r.refId.trim().isEmpty)) {
          throw StateError('Contexto inválido.');
        }
        final eventId = const Uuid().v4();
        await events.appendAndApply(
          SyncEvent(
            eventId: eventId,
            aggregateType: CategoriaFinancieraCreadaPayload.aggregateType,
            aggregateId: command.categoryId,
            eventType: CategoriaFinancieraCreadaPayload.eventType,
            deviceId: context.deviceId,
            userId: context.userId,
            createdAtLocal: DateTime.now().toUtc(),
            baseVersion: 1,
            payload: payload.toJson(),
          ),
          refs: refs,
        );
        return eventId;
      });
}