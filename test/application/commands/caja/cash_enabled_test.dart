import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:uuid/uuid.dart';
import '../../../support/cash_harness.dart';

/// El ajuste `cash_enabled` gobierna la captura sin recompilar la app.
/// Ver [[08 - Roadmap/Caja/Contrato funcional y de eventos]] revision 3.
void main() {
  late CashHarness h;
  setUp(() => h = CashHarness());
  tearDown(() => h.dispose());

  test('habilitada por defecto: el command service opera', () {
    expect(h.cash.enabled, isTrue);
  });

  test(
    'deshabilitada: abrir y cerrar se rechazan con motivo visible',
    () async {
      h.setCashEnabled(false);

      expect(h.cash.enabled, isFalse);
      await expectLater(
        h.cash.abrir(
          AbrirCajaCommand(sessionId: const Uuid().v4(), openingMinor: 10000),
        ),
        throwsStateError,
      );
      await expectLater(
        h.cash.cerrar(
          CerrarCajaCommand(sessionId: const Uuid().v4(), countedMinor: 0),
        ),
        throwsStateError,
      );
    },
  );

  test('deshabilitada: el efectivo no se asocia a ninguna caja', () async {
    h.setCashEnabled(false);

    final binding = await h.cash.binding(method: 'cash', amountMinor: 2500);

    expect(binding, isNull);
  });

  test(
    'deshabilitada: el efectivo registro fuera del cajón no genera movimiento',
    () async {
      h.setCashEnabled(false);
      final entry = await h.entry(drawer: false);

      expect(h.cash.enabled, isFalse);
      expect(entry, isNotEmpty);
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
    },
  );

  test('deshabilitada: pedir entrada al cajón se rechaza con motivo', () async {
    h.setCashEnabled(false);

    await expectLater(h.entry(drawer: true), throwsStateError);
    expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
  });

  test(
    'vuelve a habilitada en caliente: recupera operacion completa',
    () async {
      h.setCashEnabled(false);
      expect(h.cash.enabled, isFalse);

      h.setCashEnabled(true);
      final id = await h.open();
      await h.entry();

      expect(h.cash.enabled, isTrue);
      expect(
        (await h.db.select(h.db.cashMovements).get()).single.sessionId,
        id,
      );
    },
  );

  test('el ajuste no altera el modo instalado', () {
    h.setCashEnabled(false);

    expect(h.config.config.cashEnabled, isFalse);
    expect(h.config.mode, AppMode.serverSync);
  });
}
