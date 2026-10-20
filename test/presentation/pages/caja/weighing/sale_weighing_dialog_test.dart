import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_measurement.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_form_result.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_dialog.dart';

import '../../../../support/fake_scale_gateway.dart';
import '../../articulos/sale_quantity_dialog_test.dart' show conditions;
import 'sale_weighing_controller_test.dart' show profile, weight;

void main() {
  late FakeScaleGateway gateway;
  late ScaleSessionService service;
  late Duration now;
  late List<SaleQuantityFormResult?> results;
  late StreamController<SaleDraft?> drafts;

  Future<void> open(
    WidgetTester tester, {
    bool opening = false,
    bool heldEnter = false,
    double textScale = 1,
  }) async {
    gateway = FakeScaleGateway();
    if (opening) gateway.pendingOpen = Completer<void>();
    now = Duration.zero;
    service = ScaleSessionService(gateway, now: () => now);
    results = [];
    drafts = StreamController<SaleDraft?>.broadcast();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showDialog<SaleQuantityFormResult>(
                    context: context,
                    builder: (_) => SaleWeighingDialog(
                      conditions: conditions(price: 5000),
                      watchDraft: () async* {
                        yield null;
                        yield* drafts.stream;
                      },
                      profile: profile,
                      service: service,
                      loadManualConditions: () async => conditions(price: 5000),
                    ),
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    if (heldEnter) await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    drafts.add(null);
    await tester.pump();
  }

  Future<void> read(WidgetTester tester, int grams) async {
    gateway.reads.last.complete([weight(grams)]);
    await tester.pump();
    await tester.pump();
  }

  Future<void> drain(WidgetTester tester) async {
    if (gateway.pendingOpen?.isCompleted == false) {
      gateway.pendingOpen!.complete();
    }
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    await tester.pump();
  }

  Future<void> cleanup(WidgetTester tester) async {
    final closing = service.active?.close();
    await drain(tester);
    await closing;
    await tester.pumpWidget(const SizedBox());
    await drafts.close();
    await service.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed !=
      null;

  testWidgets(
    'B17/B21 Enter sufijo y repetido no confirma; nuevo Enter confirma una sola vez',
    (tester) async {
      await open(tester, heldEnter: true);
      await read(tester, 400);
      expect(find.text(r'Importe: $20.00'), findsOneWidget);
      expect(find.text(r'Precio: $50.00 / 1 kg'), findsOneWidget);
      expect(find.text('Báscula: Mostrador'), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(results, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(results.single!.measuredQuantity, '0.4');
      expect(service.active, isNull);
      await cleanup(tester);
    },
  );

  testWidgets(
    'B21/B22 botón antiguo bloquea trama pendiente de frame; doble clic congela muestra visible',
    (tester) async {
      await open(tester);
      await read(tester, 400);
      final oldAction = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      now += const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
      gateway.reads.last.complete([weight(430)]);
      // Flush the transport/stream without painting a new frame.
      await tester.idle();
      oldAction();
      expect(results, isEmpty);
      await tester.pump();
      expect(find.text(r'Importe: $21.50'), findsOneWidget);
      final action = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single!.measuredQuantity, '0.43');
      expect(results.single!.targetAmountMinor, isNull);
      await cleanup(tester);
    },
  );

  testWidgets('B19 caducidad visible sin otra trama y reintento nuevo', (
    tester,
  ) async {
    await open(tester);
    await read(tester, 400);
    now += const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(enabled(tester), isFalse);
    expect(find.textContaining('Lectura vencida'), findsOneWidget);
    expect(find.text(r'Importe: $20.00'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await drain(tester);
    await tester.pump();
    expect(find.text('Esperando lectura nueva…'), findsOneWidget);
    expect(enabled(tester), isFalse);
    await cleanup(tester);
  });

  testWidgets(
    'B22 retirar carga después de aceptar no cambia cantidad mientras cierra',
    (tester) async {
      await open(tester);
      await read(tester, 430);
      now += const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Aceptar'));
      await tester.pump();
      expect(results, isEmpty);
      gateway.reads.last.complete([weight(0)]);
      await tester.pumpAndSettle();
      expect(results.single!.measuredQuantity, '0.43');
      expect(results.single!.expectedUnitPriceMinor, 5000);
      expect(service.active, isNull);
      await cleanup(tester);
    },
  );

  for (final pending in ['open', 'read']) {
    testWidgets(
      'B23 cancelar durante $pending espera cierre y descarta respuesta tardía',
      (tester) async {
        await open(tester, opening: pending == 'open');
        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        expect(results, isEmpty);
        expect(service.active, isNotNull);
        await drain(tester);
        await tester.pumpAndSettle();
        expect(results, [null]);
        expect(service.active, isNull);
        await cleanup(tester);
      },
    );
  }

  testWidgets(
    'B23 cierre fallido permite reintento sin perder aceptación congelada',
    (tester) async {
      await open(tester);
      await read(tester, 400);
      gateway.failClose = true;
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(service.active, isNotNull);
      expect(find.text('Reintentar cierre'), findsOneWidget);
      gateway.failClose = false;
      await tester.tap(find.text('Reintentar cierre'));
      await tester.pumpAndSettle();
      expect(results.single!.measuredQuantity, '0.4');
      await cleanup(tester);
    },
  );

  for (final interruption in ['focus', 'activity', 'route']) {
    testWidgets(
      'B24 $interruption descarta lectura; reanudar exige nueva muestra',
      (tester) async {
        await open(tester);
        await read(tester, 400);
        void focus(ViewFocusState state) =>
            tester.binding.handleViewFocusChanged(
              ViewFocusEvent(
                viewId: tester.view.viewId,
                state: state,
                direction: ViewFocusDirection.undefined,
              ),
            );
        if (interruption == 'focus') {
          focus(ViewFocusState.unfocused);
        } else if (interruption == 'activity') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else {
          unawaited(
            Navigator.of(tester.element(find.byType(SaleWeighingDialog))).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Otra ruta')),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(service.active, isNull);
        if (interruption == 'focus') {
          focus(ViewFocusState.focused);
        } else if (interruption == 'activity') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          Navigator.of(tester.element(find.text('Otra ruta'))).pop();
        }
        await tester.pumpAndSettle();
        expect(find.text(r'Importe: $20.00'), findsNothing);
        expect(enabled(tester), isFalse);
        expect(gateway.calls.where((e) => e.startsWith('open')), hasLength(1));
        await tester.tap(find.text('Reanudar'));
        await tester.pump();
        expect(enabled(tester), isFalse);
        await read(tester, 430);
        expect(find.text(r'Importe: $21.50'), findsOneWidget);
        await cleanup(tester);
      },
    );
  }

  testWidgets(
    'B24 pérdida de foco durante reintento pendiente exige otra reanudación',
    (tester) async {
      await open(tester);
      await read(tester, 400);
      now += const Duration(seconds: 2);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      void focus(ViewFocusState state) => tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: state,
          direction: ViewFocusDirection.undefined,
        ),
      );
      focus(ViewFocusState.unfocused);
      focus(ViewFocusState.focused);
      await drain(tester);
      await tester.pumpAndSettle();
      expect(service.active, isNull);
      expect(gateway.calls.where((e) => e.startsWith('open')), hasLength(1));
      expect(enabled(tester), isFalse);
      await tester.tap(find.text('Reanudar'));
      await tester.pump();
      expect(service.active, isNotNull);
      await cleanup(tester);
    },
  );

  testWidgets(
    'B23 manual explícita libera sesión y no conserva peso; cancelar devuelve null',
    (tester) async {
      await open(tester);
      await read(tester, 400);
      await tester.tap(find.text('Captura manual'));
      await tester.pumpAndSettle();
      expect(service.active, isNull);
      expect(find.byType(SaleQuantityDialog), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('sale-measured-quantity')),
      );
      expect(field.controller!.text, isEmpty);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      expect(results, [null]);
      await cleanup(tester);
    },
  );

  testWidgets(
    'B23 retirada externa durante conexión libera sesión y suscripciones',
    (tester) async {
      await open(tester, opening: true);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      expect(service.active, isNull);
      await cleanup(tester);
    },
  );

  testWidgets(
    'B36 pantalla reducida texto 2x peso importe error y acciones accesibles',
    (tester) async {
      tester.view.physicalSize = const Size(480, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, textScale: 2);
      await read(tester, 430);
      expect(find.text(r'Importe: $21.50'), findsOneWidget);
      await tester.ensureVisible(find.text('Aceptar'));
      expect(tester.takeException(), isNull);
      now += const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
      gateway.reads.last.complete([
        const ScaleMeasurement(failure: ScaleFailure.unsupportedUnit),
      ]);
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Unidad de lectura no compatible.'));
      expect(enabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );
}
