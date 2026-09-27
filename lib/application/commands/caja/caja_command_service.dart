import 'package:uuid/uuid.dart';
import '../../config/app_config_controller.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/caja_abierta_payload.dart';
import '../../sync/payloads/caja_cerrada_payload.dart';
import '../../sync/payloads/cash_binding_payload.dart';
import '../../sync/payloads/categoria_financiera_creada_payload.dart';
import '../../sync/projections/cash_projection_store.dart';
import '../local_command_context.dart';
import 'abrir_caja_command.dart';
import 'cerrar_caja_command.dart';

class CajaCommandService {
  CajaCommandService({
    required this.store,
    required this.events,
    required this.context,
    required this.config,
  });
  final CashProjectionStore store;
  final LocalEventStore events;
  final LocalCommandContext context;
  final AppConfigController config;
  void _checkEnabled() {
    if (!enabled) {
      throw StateError('La captura de caja aún no está habilitada.');
    }
  }

  /// Cambiar el ajuste no reinicia la app: se consulta en cada uso.
  bool get enabled => config.config.cashEnabled;

  Future<CashBindingPayload?> binding({
    required String method,
    required int amountMinor,
    bool affectsDrawer = true,
  }) async {
    if (!affectsDrawer || !enabled || method != 'cash' || amountMinor == 0) {
      return null;
    }
    final session = await store.current(context.deviceId);
    if (session == null) {
      throw StateError(
        'Abre la caja de esta terminal antes de registrar efectivo.',
      );
    }
    return CashBindingPayload(
      sessionId: session.id,
      openingEventId: session.createdEventId!,
      movementId: const Uuid().v4(),
    );
  }

  Future<String> abrir(AbrirCajaCommand c) => store.atomic(() async {
    _checkEnabled();
    cashNonnegative(c.openingMinor);
    final previous = await store.find(c.sessionId);
    if (previous != null) {
      if (previous.deviceId != context.deviceId ||
          previous.openingMinor != c.openingMinor) {
        throw StateError('Esta apertura ya existe con otros datos.');
      }
      return previous.createdEventId!;
    }
    final latest = await store.latest(context.deviceId);
    if (latest?.status == 'open') {
      throw StateError('Ya existe una caja abierta en esta terminal.');
    }
    final p = CajaAbiertaPayload(
      openingMinor: c.openingMinor,
      openedAtMs: DateTime.now().millisecondsSinceEpoch,
      previousCloseEventId: latest?.lastEventId,
    );
    return _append(c.sessionId, CajaAbiertaPayload.eventType, p.toJson(), [
      LocalEventRef.affects(
        refType: CajaAbiertaPayload.aggregateType,
        refId: c.sessionId,
      ),
      LocalEventRef.requiresUnique(
        refType: 'cash_device',
        refId: context.deviceId,
      ),
      if (latest != null)
        LocalEventRef.uses(
          refType: CajaAbiertaPayload.aggregateType,
          refId: latest.id,
        ),
    ]);
  });
  Future<String> cerrar(CerrarCajaCommand c) => store.atomic(() async {
    _checkEnabled();
    cashNonnegative(c.countedMinor);
    final s = await store.find(c.sessionId);
    if (s == null || s.deviceId != context.deviceId) {
      throw StateError('La caja pertenece a otra terminal o no existe.');
    }
    final notes = financialOptionalText(c.notes, 'notes', 500);
    if (s.status == 'closed') {
      if (s.close!.countedMinor != c.countedMinor || s.close!.notes != notes) {
        throw StateError('El corte ya es inmutable.');
      }
      return s.lastEventId!;
    }
    final movements = await store.movements(s.id);
    final incoming = movements
        .where((m) => m.direction == 'in')
        .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
    final outgoing = movements
        .where((m) => m.direction == 'out')
        .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
    final expected = BigInt.from(s.openingMinor) + incoming - outgoing;
    final p = CajaCerradaPayload(
      openingEventId: s.createdEventId!,
      closedAtMs: DateTime.now().millisecondsSinceEpoch,
      countedMinor: c.countedMinor,
      incomeMinor: incoming.toString(),
      expenseMinor: outgoing.toString(),
      expectedMinor: expected.toString(),
      differenceMinor: (BigInt.from(c.countedMinor) - expected).toString(),
      notes: notes,
      movements: movements,
    );
    return _append(s.id, CajaCerradaPayload.eventType, p.toJson(), [
      LocalEventRef.affects(
        refType: CajaCerradaPayload.aggregateType,
        refId: s.id,
      ),
      LocalEventRef.uses(
        refType: CajaCerradaPayload.aggregateType,
        refId: s.id,
      ),
      for (final m in movements)
        LocalEventRef.uses(refType: 'cash_movement', refId: m.movementId),
    ]);
  });
  Future<String> _append(
    String id,
    String type,
    Map<String, Object?> payload,
    List<LocalEventRef> refs,
  ) async {
    if (context.deviceId.trim().isEmpty ||
        context.userId.trim().isEmpty ||
        refs.any((r) => r.refId.trim().isEmpty)) {
      throw StateError('Contexto o referencias inválidos.');
    }
    final eventId = const Uuid().v4();
    await events.appendAndApply(
      SyncEvent(
        eventId: eventId,
        aggregateType: CajaAbiertaPayload.aggregateType,
        aggregateId: id,
        eventType: type,
        deviceId: context.deviceId,
        userId: context.userId,
        createdAtLocal: DateTime.now().toUtc(),
        baseVersion: 1,
        payload: payload,
      ),
      refs: refs,
    );
    return eventId;
  }
}
