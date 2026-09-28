import 'package:uuid/uuid.dart';

import '../../config/app_config_controller.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/saldo_cuenta_inicial_declarado_payload.dart';
import '../../sync/projections/account_balance_baseline_projection_store.dart';
import '../local_command_context.dart';
import 'declarar_saldo_cuenta_inicial_command.dart';

/// Comando de declaración del saldo inicial de la cuenta bancaria.
///
/// Es un hecho único e inmutable (D2), no una sesión: no abre ni cierra nada y
/// no se toca caja. `as_of_ms` se sella en el instante de la declaración; la
/// política de esa frontera es de la Fase 4.
///
/// La unicidad NO es por terminal: el slot se resuelve con un `refId`
/// constante (`account_balance_slot` / `unica`) en `requires_unique`, así que
/// el servidor la hace global sin agregar `account_id` (fuera de alcance, R4).
class CuentaCommandService {
  CuentaCommandService({
    required this.store,
    required this.events,
    required this.context,
    required this.config,
  });

  final AccountBalanceBaselineProjectionStore store;
  final LocalEventStore events;
  final LocalCommandContext context;
  final AppConfigController config;

  /// Cambiar el ajuste no reinicia la app: se consulta en cada uso.
  bool get enabled => config.config.bankEnabled;

  void _checkEnabled() {
    if (!enabled) {
      throw StateError('El saldo en cuenta aún no está habilitado.');
    }
  }

  Future<String> declarar(DeclararSaldoCuentaInicialCommand c) =>
      store.atomic(() async {
        _checkEnabled();
        bankBalanceMinor(c.amountMinor);
        final previous = await store.find(c.baselineId);
        if (previous != null) {
          if (previous.deviceId != context.deviceId ||
              previous.amountMinor != c.amountMinor) {
            throw StateError('Esta declaración ya existe con otros datos.');
          }
          return previous.createdEventId!;
        }
        if (await store.only() != null) {
          throw StateError('El saldo inicial ya fue declarado.');
        }
        final p = SaldoCuentaInicialDeclaradoPayload.fromJson({
          'amount_minor': c.amountMinor,
          'as_of_ms': DateTime.now().millisecondsSinceEpoch,
        });
        return _append(c.baselineId, p.toJson(), [
          LocalEventRef.affects(
            refType: SaldoCuentaInicialDeclaradoPayload.aggregateType,
            refId: c.baselineId,
          ),
          LocalEventRef.requiresUnique(
            refType: SaldoCuentaInicialDeclaradoPayload.slotRefType,
            refId: SaldoCuentaInicialDeclaradoPayload.slotRefId,
          ),
        ]);
      });

  Future<String> _append(
    String id,
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
        aggregateType: SaldoCuentaInicialDeclaradoPayload.aggregateType,
        aggregateId: id,
        eventType: SaldoCuentaInicialDeclaradoPayload.eventType,
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
