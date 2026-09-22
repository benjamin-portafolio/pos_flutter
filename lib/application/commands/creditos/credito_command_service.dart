import 'package:uuid/uuid.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/abono_cliente_registrado_payload.dart';
import '../../sync/payloads/inventory_movement_payload.dart';
import '../../sync/projections/customer_credit_store.dart';
import '../../sync/projections/cliente_projection_store.dart';
import '../local_command_context.dart';
import 'registrar_abono_command.dart';

class CreditoCommandService {
  CreditoCommandService({
    required this.store,
    required this.clientes,
    required this.events,
    required this.context,
  });
  final CustomerCreditStore store;
  final ClienteProjectionStore clientes;
  final LocalEventStore events;
  final LocalCommandContext context;
  Future<String> registrarAbono(RegistrarAbonoCommand command) =>
      store.atomic(() async {
        InventoryMovementPayload.requiredUuidV4(command.id, 'abono_id');
        final cliente = await clientes.findById(command.clienteId);
        if (cliente == null ||
            !cliente.active ||
            cliente.createdEventId == null) {
          throw StateError('El cliente no está disponible.');
        }
        final payload = AbonoClienteRegistradoPayload(
          clienteId: cliente.id,
          clienteEventId: cliente.createdEventId!,
          amountMinor: command.amountMinor,
          method: command.method,
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
          reference: command.reference,
        );
        final previous = await store.paymentEvent(command.id);
        if (previous != null) {
          final p = AbonoClienteRegistradoPayload.fromJson(previous.payload);
          if (p.clienteId != payload.clienteId ||
              p.amountMinor != payload.amountMinor ||
              p.method != payload.method ||
              p.reference != payload.reference) {
            throw StateError('Este abono ya se registró con otros datos.');
          }
          return previous.eventId;
        }
        final refs = payload.refs(command.id);
        if (context.userId.trim().isEmpty ||
            context.deviceId.trim().isEmpty ||
            refs.any((r) => r.refId.trim().isEmpty)) {
          throw StateError('Contexto inválido.');
        }
        final eventId = const Uuid().v4();
        await events.appendAndApply(
          SyncEvent(
            eventId: eventId,
            aggregateType: AbonoClienteRegistradoPayload.aggregateType,
            aggregateId: command.id,
            eventType: AbonoClienteRegistradoPayload.eventType,
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
