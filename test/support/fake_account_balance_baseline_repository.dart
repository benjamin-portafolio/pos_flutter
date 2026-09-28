import 'dart:async';

import 'package:pos_flutter/domain/cuenta/account_balance_baseline.dart';
import 'package:pos_flutter/domain/repositories/account_balance_baseline_repository.dart';

/// Doble de `AccountBalanceBaselineRepository` para pruebas de pantalla.
///
/// Al suscribirse emite el valor vigente y después cada cambio, igual que el
/// repositorio real de Drift, que re-emite el resultado actual de la consulta.
class FakeAccountBalanceBaselineRepository
    implements AccountBalanceBaselineRepository {
  FakeAccountBalanceBaselineRepository([AccountBalanceBaseline? baseline])
      : _baseline = baseline;

  AccountBalanceBaseline? _baseline;
  final _controller = StreamController<AccountBalanceBaseline?>.broadcast();

  AccountBalanceBaseline? get baseline => _baseline;

  /// Cambia el hecho declarado y avisa a los suscriptores, como cuando llega
  /// por sync o el servidor confirma la entrega.
  set baseline(AccountBalanceBaseline? value) {
    _baseline = value;
    _controller.add(value);
  }

  @override
  Stream<AccountBalanceBaseline?> watchBaseline() async* {
    yield _baseline;
    yield* _controller.stream;
  }

  void dispose() => _controller.close();
}

/// Baseline de prueba con la foto y el corte `asOfMs` que cada test necesite.
AccountBalanceBaseline baselinePrueba({
  int amountMinor = 25000000,
  int asOfMs = 0,
  String deliveryStatus = 'delivered',
}) => AccountBalanceBaseline(
  id: 'baseline-1',
  deviceId: 'bank-tablet',
  declaredByUserId: 'bank-user',
  amountMinor: amountMinor,
  asOfMs: asOfMs,
  createdEventId: 'event-baseline',
  lastEventId: 'event-baseline',
  deliveryStatus: deliveryStatus,
);