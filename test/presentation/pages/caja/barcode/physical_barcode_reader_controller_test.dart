import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/physical_barcode_read_admission.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/physical_barcode_reader_controller.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/sale_barcode_read_outcome.dart';

import '../../../../support/barcode_sale_fixture.dart';

void main() {
  late BarcodeSaleFixture fixture;
  late PhysicalBarcodeReaderController reader;
  late Future<VariantePorCodigoBarras?> Function(List<VariantePorCodigoBarras>)
  select;
  late Future<String?> Function(VariantePorCodigoBarras) quantity;
  late List<SaleBarcodeReadOutcome> outcomes;

  setUp(() async {
    fixture = BarcodeSaleFixture();
    await fixture.seed();
    select = (_) async => throw StateError('Selector inesperado');
    quantity = (_) async => throw StateError('Cantidad inesperada');
    reader = PhysicalBarcodeReaderController(
      coordinator: fixture.coordinator,
      selectProduct: (candidates) => select(candidates),
      requestQuantity: (candidate) => quantity(candidate),
    );
    outcomes = [];
    Object? previous;
    reader.addListener(() {
      final result = reader.lastResult;
      if (result != null && !identical(result, previous)) {
        outcomes.add(result.outcome);
        previous = result;
      }
    });
  });
  tearDown(() async {
    reader.dispose();
    await reader.done;
    await fixture.dispose();
  });

  void accept(String code) {
    expect(reader.submit(code), PhysicalBarcodeReadAdmission.accepted);
  }

  test('inicia desactivado y no revive después de terminar', () async {
    expect(reader.isAccepting, isFalse);
    expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
    reader.activate();
    reader.activate();
    expect(reader.isAccepting, isTrue);
    reader.pause();
    expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
    reader.resume();
    expect(reader.isAccepting, isTrue);
    await reader.finish();
    reader.activate();
    reader.resume();
    expect(reader.isFinished, isTrue);
    expect(() => reader.addListener(() {}), throwsFlutterError);
    expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
    await fixture.expectNoWrites();
  });

  for (final mode in AppMode.values) {
    test('FIFO A → B → A durante consulta real en ${mode.name}', () async {
      fixture.config.update(AppConfig.initial.copyWith(mode: mode));
      final gate = Completer<void>();
      fixture.beforeLookup = (code) =>
          fixture.lookups.length == 1 ? gate.future : Future.value();
      reader.activate();
      accept('001');
      accept('002');
      accept('001');
      expect(reader.isAccepting, isTrue);
      expect(reader.pendingReadCount, 2);
      expect(reader.unstartedReadCount, 3);
      expect(fixture.lookups, ['001']);
      final finished = reader.finish();
      expect(reader.isFinishing, isTrue);
      expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
      gate.complete();
      await finished;
      expect(fixture.lookups, ['001', '002', '001']);
      expect(fixture.attempts.map((c) => c.variantId), ['A', 'B', 'A']);
      final payloads = await fixture.payloads();
      expect(payloads.map((p) => p.item.variantId), ['A', 'B', 'A']);
      expect(payloads.map((p) => p.item.quantity), [1, 1, 2]);
      expect((await fixture.draft)!.items.map((i) => i.quantity), [2, 1]);
      expect((await fixture.draft)!.totalMinor, 300);
      expect(reader.pendingReadCount, 0);
      expect(reader.unstartedReadCount, 0);
      expect(reader.isProcessing, isFalse);
      final events = await fixture.db.select(fixture.db.events).get();
      expect(events, hasLength(3));
      expect(events.map((e) => e.eventId).toSet(), hasLength(3));
      expect(events.every((e) => e.deliveryStatus == 'not_required'), isTrue);
      expect(await fixture.db.eventDao.obtenerEventosPendientes(), isEmpty);
      expect(
        await fixture.db.select(fixture.db.eventRefs).get(),
        hasLength(mode == AppMode.standalone ? 0 : 12),
      );
    });
  }

  test('tres códigos iguales durante guardado son tres intenciones', () async {
    final gate = Completer<void>();
    fixture.beforeSave = (_) =>
        fixture.attempts.length == 1 ? gate.future : Future.value();
    reader.activate();
    accept('001');
    await fixture.waitFor(() => fixture.attempts.isNotEmpty);
    expect(reader.isSaving, isTrue);
    expect(reader.isAccepting, isTrue);
    accept('001');
    accept('001');
    expect(reader.pendingReadCount, 2);
    expect(reader.unstartedReadCount, 2);
    expect(fixture.lookups, ['001']);
    await fixture.expectNoWrites();
    final finished = reader.finish();
    gate.complete();
    await finished;
    expect(fixture.attempts, hasLength(3));
    expect((await fixture.draft)!.items.single.quantity, 3);
    expect((await fixture.payloads()).map((p) => p.item.quantity), [1, 2, 3]);
  });

  test('trim y NFKC conservan ceros iniciales, vacío no agrega', () async {
    reader.activate();
    expect(reader.submit(' \n '), PhysicalBarcodeReadAdmission.empty);
    expect(reader.submit(''), PhysicalBarcodeReadAdmission.empty);
    accept(' ００１\r\n');
    await reader.finish();
    expect(fixture.lookups, ['001']);
    expect(fixture.attempts.single.variantId, 'A');
    expect((await fixture.payloads()).single.item.quantity, 1);
  });

  for (final input in ['A001', '00A1', '001A', '00 1', '00\n1', '1' * 33]) {
    test('rechaza íntegramente ${input.replaceAll('\n', r'\n')}', () async {
      reader.activate();
      expect(reader.submit(input), PhysicalBarcodeReadAdmission.invalid);
      await reader.finish();
      expect(fixture.lookups, isEmpty);
      expect(fixture.attempts, isEmpty);
      await fixture.expectNoWrites();
    });
  }

  test('acepta el límite de 32 dígitos sin truncarlo', () async {
    reader.activate();
    accept('0' * 32);
    await reader.finish();
    expect(fixture.lookups, ['0' * 32]);
    expect(outcomes, [SaleBarcodeReadOutcome.notFound]);
    await fixture.expectNoWrites();
  });

  test(
    'desconocido seguido de conocido continúa sin escribir el primero',
    () async {
      reader.activate();
      accept('999');
      accept('001');
      await reader.finish();
      expect(outcomes, [
        SaleBarcodeReadOutcome.notFound,
        SaleBarcodeReadOutcome.added,
      ]);
      expect(fixture.lookups, ['999', '001']);
      expect(fixture.attempts, hasLength(1));
      expect(await fixture.payloads(), hasLength(1));
    },
  );

  for (final cancelled in [true, false]) {
    test(
      'selector pausa admisión y conserva FIFO, cancelado=$cancelled',
      () async {
        final dialog = Completer<VariantePorCodigoBarras?>();
        select = (candidates) async {
          expect(reader.isPaused, isTrue);
          expect(reader.isAccepting, isFalse);
          expect(reader.pendingReadCount, 1);
          return dialog.future;
        };
        reader.activate();
        accept('003');
        accept('001');
        await fixture.waitFor(() => reader.isPaused);
        expect(reader.submit('002'), PhysicalBarcodeReadAdmission.notAccepting);
        final candidates = await fixture.products
            .buscarVariantesPorCodigoBarras('003');
        dialog.complete(cancelled ? null : candidates.last);
        await reader.finish();
        expect(outcomes, [
          cancelled
              ? SaleBarcodeReadOutcome.selectionCancelled
              : SaleBarcodeReadOutcome.added,
          SaleBarcodeReadOutcome.added,
        ]);
        expect(
          fixture.attempts.map((c) => c.variantId),
          cancelled ? ['A'] : ['D', 'A'],
        );
      },
    );
  }

  test(
    'cancelar cantidad conserva lo aceptado y no crea evento medido',
    () async {
      final dialog = Completer<String?>();
      quantity = (_) => dialog.future;
      reader.activate();
      accept('004');
      accept('001');
      await fixture.waitFor(() => reader.isPaused);
      expect(reader.pendingReadCount, 1);
      expect(reader.submit('002'), PhysicalBarcodeReadAdmission.notAccepting);
      dialog.complete(null);
      await reader.finish();
      expect(outcomes, [
        SaleBarcodeReadOutcome.quantityCancelled,
        SaleBarcodeReadOutcome.added,
      ]);
      expect(fixture.attempts.single.variantId, 'A');
      expect(await fixture.payloads(), hasLength(1));
    },
  );

  test(
    'pausa externa durante diálogo requiere reanudación explícita',
    () async {
      final dialog = Completer<String?>();
      quantity = (_) => dialog.future;
      reader.activate();
      accept('004');
      accept('001');
      await fixture.waitFor(() => reader.isPaused);
      reader.pause();
      dialog.complete('0.750');
      await Future<void>.delayed(Duration.zero);
      expect(fixture.attempts, isEmpty);
      expect(reader.isPaused, isTrue);
      final finished = reader.finish();
      reader.resume();
      await finished;
      expect(fixture.attempts.map((c) => c.variantId), ['M', 'A']);
      expect((await fixture.draft)!.totalMinor, 15100);
    },
  );

  for (final code in ['001', '003', '004']) {
    test(
      'pausa durante consulta de $code congela pasos hasta reanudar',
      () async {
        final gate = Completer<void>();
        fixture.beforeLookup = (_) => gate.future;
        var interactions = 0;
        select = (_) async {
          interactions++;
          return null;
        };
        quantity = (_) async {
          interactions++;
          return null;
        };
        reader.activate();
        accept(code);
        accept('002');
        reader.pause();
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(interactions, 0);
        expect(fixture.attempts, isEmpty);
        expect(reader.pendingReadCount, 1);
        final finished = reader.finish();
        expect(reader.isFinished, isFalse);
        reader.resume();
        expect(reader.isAccepting, isFalse); // Drenar no reactiva admisión.
        await finished;
        expect(interactions, code == '001' ? 0 : 1);
        expect(fixture.lookups, [code, '002']);
      },
    );
  }

  test(
    'pausa durante comando permite commit y congela siguiente consulta',
    () async {
      final gate = Completer<void>();
      fixture.beforeSave = (_) => gate.future;
      reader.activate();
      accept('001');
      accept('002');
      await fixture.waitFor(() => fixture.attempts.isNotEmpty);
      reader.pause();
      gate.complete();
      await fixture.waitFor(() => !reader.isProcessing);
      expect(fixture.lookups, ['001']);
      expect(reader.pendingReadCount, 1);
      expect((await fixture.draft)!.items.single.variantId, 'A');
      expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
      reader.resume();
      await reader.finish();
      expect(fixture.lookups, ['001', '002']);
      expect((await fixture.draft)!.totalMinor, 200);
    },
  );

  for (final mode in AppMode.values) {
    test('error real SQLite pausa sin reintentar en ${mode.name}', () async {
      fixture.config.update(AppConfig.initial.copyWith(mode: mode));
      await fixture.db.customStatement(
        "CREATE TRIGGER reject_read BEFORE INSERT ON sale_items BEGIN SELECT RAISE(ABORT, 'fallo de guardado'); END",
      );
      reader.activate();
      accept('001');
      accept('002');
      await fixture.waitFor(() => !reader.isProcessing);
      expect(reader.error, isNotNull);
      expect(reader.isPaused, isTrue);
      expect(reader.lastResult, isNull);
      expect(reader.pendingReadCount, 1);
      expect(fixture.attempts.map((c) => c.variantId), ['A']);
      expect(reader.submit('001'), PhysicalBarcodeReadAdmission.notAccepting);
      await fixture.expectNoWrites();
      final finished = reader.finish();
      expect(reader.isFinished, isFalse);
      await fixture.db.customStatement('DROP TRIGGER reject_read');
      reader.resume();
      await finished;
      expect(reader.error, isNull);
      expect(fixture.attempts.map((c) => c.variantId), ['A', 'B']);
      expect((await fixture.draft)!.items.single.variantId, 'B');
      expect(await fixture.payloads(), hasLength(1));
      expect(outcomes, [SaleBarcodeReadOutcome.added]);
    });
  }

  test(
    'error de consulta también pausa y se puede descartar el resto',
    () async {
      fixture.beforeLookup = (_) async => throw StateError('consulta fallida');
      reader.activate();
      accept('001');
      accept('002');
      await fixture.waitFor(() => !reader.isProcessing);
      expect(reader.error, isStateError);
      expect(reader.pendingReadCount, 1);
      await reader.finish(discardPending: true);
      expect(reader.pendingReadCount, 0);
      expect(fixture.lookups, ['001']);
      await fixture.expectNoWrites();
    },
  );

  test(
    'error después del commit no reintenta una respuesta incierta',
    () async {
      fixture.afterSave = (command) async {
        if (command.variantId == 'A') throw StateError('respuesta incierta');
      };
      reader.activate();
      accept('001');
      accept('002');
      await fixture.waitFor(() => !reader.isProcessing);
      expect(reader.error, isStateError);
      expect(outcomes, isEmpty);
      expect(reader.pendingReadCount, 1);
      expect((await fixture.draft)!.items.single.quantity, 1);
      final finished = reader.finish();
      reader.resume();
      await finished;
      expect(fixture.attempts.map((c) => c.variantId), ['A', 'B']);
      expect((await fixture.draft)!.items.map((i) => i.quantity), [1, 1]);
      expect(await fixture.payloads(), hasLength(2));
    },
  );

  test(
    'pausar desde el estado de diálogo impide presentarlo hasta reanudar',
    () async {
      var requested = false;
      var paused = false;
      select = (_) async {
        requested = true;
        return null;
      };
      reader.addListener(() {
        if (reader.isPaused && !paused) {
          paused = true;
          reader.pause();
        }
      });
      reader.activate();
      accept('003');
      await fixture.waitFor(() => paused);
      expect(requested, isFalse);
      reader.resume();
      await reader.finish();
      expect(requested, isTrue);
      await fixture.expectNoWrites();
    },
  );

  test(
    'una consulta de la sesión anterior no altera la sesión siguiente',
    () async {
      final gate = Completer<void>();
      var interactions = 0;
      select = (_) async {
        interactions++;
        return null;
      };
      fixture.beforeLookup = (code) =>
          code == '003' ? gate.future : Future.value();
      reader.activate();
      accept('003');
      final oldFinished = reader.finish(discardPending: true);
      final next = PhysicalBarcodeReaderController(
        coordinator: fixture.coordinator,
        selectProduct: (_) async =>
            throw StateError('Diálogo de sesión antigua'),
        requestQuantity: (_) async => throw StateError('Cantidad inesperada'),
      );
      next.activate();
      expect(next.submit('001'), PhysicalBarcodeReadAdmission.accepted);
      await next.finish();
      gate.complete();
      await oldFinished;
      expect(interactions, 0);
      expect(fixture.attempts.single.variantId, 'A');
      expect((await fixture.draft)!.items.single.quantity, 1);
      expect(reader.error, isNull);
      expect(() => next.addListener(() {}), throwsFlutterError);
    },
  );

  for (final code in ['001', '003', '004']) {
    test(
      'consulta tardía de $code al descartar no abre diálogo ni comando',
      () async {
        final gate = Completer<void>();
        var interactions = 0;
        select = (_) async {
          interactions++;
          return null;
        };
        quantity = (_) async {
          interactions++;
          return null;
        };
        fixture.beforeLookup = (_) => gate.future;
        reader.activate();
        accept(code);
        accept('002');
        final finished = reader.finish(discardPending: true);
        expect(reader.pendingReadCount, 0);
        gate.complete();
        await finished;
        expect(interactions, 0);
        expect(fixture.lookups, [code]);
        expect(fixture.attempts, isEmpty);
        await fixture.expectNoWrites();
      },
    );
  }

  for (final measured in [false, true]) {
    test(
      'respuesta de diálogo tras terminar no agrega, medida=$measured',
      () async {
        final selection = Completer<VariantePorCodigoBarras?>();
        final amount = Completer<String?>();
        select = (_) => selection.future;
        quantity = (_) => amount.future;
        reader.activate();
        accept(measured ? '004' : '003');
        accept('001');
        await fixture.waitFor(() => reader.isPaused);
        final finished = reader.finish(discardPending: true);
        if (measured) {
          amount.complete('0.750');
        } else {
          selection.complete(
            (await fixture.products.buscarVariantesPorCodigoBarras(
              '003',
            )).first,
          );
        }
        await finished;
        expect(fixture.attempts, isEmpty);
        expect(reader.pendingReadCount, 0);
        await fixture.expectNoWrites();
      },
    );
  }

  test(
    'descartar durante guardado espera commit y no inicia la siguiente',
    () async {
      final gate = Completer<void>();
      fixture.beforeSave = (_) => gate.future;
      reader.activate();
      accept('001');
      accept('002');
      await fixture.waitFor(() => fixture.attempts.isNotEmpty);
      final finished = reader.finish(discardPending: true);
      expect(reader.isFinished, isFalse);
      expect(reader.pendingReadCount, 0);
      gate.complete();
      await finished;
      expect(fixture.lookups, ['001']);
      expect((await fixture.draft)!.items.single.variantId, 'A');
      expect(await fixture.payloads(), hasLength(1));
    },
  );

  test('notificación de guardado puede terminar sin iniciar comando', () async {
    reader.addListener(() {
      if (reader.isSaving) unawaited(reader.finish(discardPending: true));
    });
    reader.activate();
    accept('001');
    await reader.done;
    expect(fixture.attempts, isEmpty);
    await fixture.expectNoWrites();
  });

  test('notificación de diálogo puede terminar antes de presentarlo', () async {
    var requested = false;
    select = (_) async {
      requested = true;
      return null;
    };
    reader.addListener(() {
      if (reader.isPaused) unawaited(reader.finish(discardPending: true));
    });
    reader.activate();
    accept('003');
    await reader.done;
    expect(requested, isFalse);
    expect(reader.error, isNull);
    await fixture.expectNoWrites();
  });

  for (final saving in [false, true]) {
    test(
      'dispose libera listeners y deja finalizar solo el comando iniciado=$saving',
      () async {
        final gate = Completer<void>();
        if (saving) {
          fixture.beforeSave = (_) => gate.future;
        } else {
          fixture.beforeLookup = (_) => gate.future;
        }
        var notifications = 0;
        reader.addListener(() => notifications++);
        reader.activate();
        accept('001');
        accept('002');
        if (saving) await fixture.waitFor(() => fixture.attempts.isNotEmpty);
        reader.dispose();
        final before = notifications;
        gate.complete();
        await reader.done;
        expect(notifications, before);
        expect(() => reader.addListener(() {}), throwsFlutterError);
        expect(reader.pendingReadCount, 0);
        expect(fixture.lookups, ['001']);
        expect(await fixture.payloads(), hasLength(saving ? 1 : 0));
      },
    );
  }
}
