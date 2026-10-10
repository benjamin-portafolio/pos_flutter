import 'package:uuid/uuid.dart';
import '../../config/app_config.dart';
import '../../config/app_config_controller.dart';
import '../../sync/local_event_store.dart';
import '../../sync/synced_event_history.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/proveedor_creado_payload.dart';
import '../../sync/payloads/proveedor_actualizado_payload.dart';
import '../../sync/projections/proveedor_projection_store.dart';
import '../local_command_context.dart';
import 'crear_proveedor_command.dart';
import 'editar_proveedor_command.dart';

class ProveedorCommandService {
  ProveedorCommandService({
    required LocalEventStore eventStore,
    required ProveedorProjectionStore projectionStore,
    required LocalCommandContext commandContext,
    required AppConfigController config,
    required SyncedEventHistory history,
  }) : _events = eventStore,
       _store = projectionStore,
       _context = commandContext,
       _config = config,
       _history = history;

  final SyncedEventHistory _history;
  final LocalEventStore _events;
  final ProveedorProjectionStore _store;
  final LocalCommandContext _context;
  final AppConfigController _config;
  final _uuid = const Uuid();

  Future<void> crearProveedor(CrearProveedorCommand command) =>
      _store.atomic(() async {
        final payload = ProveedorCreadoPayload(
          name: command.nombre,
          phone: command.telefono,
          notes: command.notas,
        );
        final event = SyncEvent(
          eventId: _uuid.v4(),
          aggregateId: _uuid.v4(),
          aggregateType: ProveedorCreadoPayload.aggregateType,
          eventType: ProveedorCreadoPayload.eventType,
          deviceId: _context.deviceId,
          userId: _context.userId,
          baseVersion: 1,
          createdAtLocal: DateTime.now(),
          payload: payload.toJson(),
        );
        await _append(event);
      });

  Future<void> editarProveedor(EditarProveedorCommand command) => _store.atomic(
    () async {
      final after = ProveedorCreadoPayload(
        name: command.nombre,
        phone: command.telefono,
        notes: command.notas,
      );
      final base = command.base;
      final before = ProveedorCreadoPayload(
        name: base.nombre,
        phone: base.telefono,
        notes: base.notas,
      );
      final current = await _store.findById(base.id);
      if (current == null ||
          !current.active ||
          base.lastEventId == null ||
          current.lastEventId != base.lastEventId ||
          current.version != base.version ||
          current.lastServerSequence != base.lastServerSequence ||
          !ProveedorActualizadoPayload.sameState(current.state, before)) {
        throw StateError('El proveedor cambió desde que se abrió la edición.');
      }
      if (_config.mode == AppMode.serverSync &&
          (await _history.eventById(base.lastEventId!))?.deliveryStatus ==
              'not_required') {
        throw StateError(
          'El historial local requiere una importación explícita.',
        );
      }
      if (ProveedorActualizadoPayload.sameState(before, after)) return;
      final payload = ProveedorActualizadoPayload(
        baseEventId: base.lastEventId!,
        before: before,
        after: after,
      );
      await _append(
        SyncEvent(
          eventId: _uuid.v4(),
          aggregateId: current.id,
          aggregateType: ProveedorActualizadoPayload.aggregateType,
          eventType: ProveedorActualizadoPayload.eventType,
          deviceId: _context.deviceId,
          userId: _context.userId,
          baseVersion: base.version,
          baseServerSequence:
              (await _history.eventById(base.lastEventId!))?.deliveryStatus ==
                  'pending'
              ? null
              : base.lastServerSequence,
          createdAtLocal: DateTime.now(),
          payload: payload.toJson(),
        ),
      );
    },
  );

  Future<void> _append(SyncEvent event) => _events.appendAndApply(
    event,
    refs: [
      LocalEventRef.affects(
        refType: ProveedorCreadoPayload.aggregateType,
        refId: event.aggregateId,
      ),
    ],
  );
}
