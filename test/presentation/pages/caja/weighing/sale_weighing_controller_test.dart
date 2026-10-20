import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_measurement.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_weight.dart';
import 'package:pos_flutter/domain/ventas/measured_sale_calculator.dart';
import 'package:pos_flutter/domain/ventas/measured_sale_conditions.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/articulos/measured_sale_preview.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_controller.dart';

import '../../../../support/fake_scale_gateway.dart';
import '../../articulos/sale_quantity_dialog_test.dart'
    show conditions, draftWith;

final profile = ScaleProfile(
  id: 'scale',
  alias: 'Mostrador',
  port: 'COM9',
  systemId: 'fake',
);

ScaleMeasurement weight(int grams) => ScaleMeasurement(
  weight: ScaleWeight(
    coefficient: BigInt.from(grams),
    decimalPlaces: 3,
    unit: ScaleUnit.kg,
    grams: grams,
  ),
);

void main() {
  late FakeScaleGateway gateway;
  late ScaleSessionService service;
  late SaleWeighingController controller;
  late Duration now;
  late StreamController<SaleDraft?> drafts;

  Future<void> open(_Pump tester, {MeasuredSaleConditions? catalog}) async {
    now = Duration.zero;
    gateway = FakeScaleGateway();
    service = ScaleSessionService(gateway, now: () => now);
    drafts = StreamController<SaleDraft?>();
    controller = SaleWeighingController(
      conditions: catalog ?? conditions(price: 5000),
      profile: profile,
      service: service,
      draft: drafts.stream,
    );
    controller.start();
    drafts.add(null);
    await tester.pump();
  }

  Future<void> read(_Pump tester, ScaleMeasurement value) async {
    if (gateway.reads.last.isCompleted) {
      now += const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
    }
    while (gateway.reads.last.isCompleted) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    gateway.reads.last.complete([value]);
    await tester.pump();
  }

  Future<void> close(_Pump tester) async {
    final closing = controller.stop();
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    await tester.pump();
    await closing;
    controller.dispose();
    final draftClosing = drafts.close();
    await tester.pump();
    await draftClosing;
    expect(service.active, isNull);
    await tester.pump();
  }

  test(
    'B16 nueva sesión no hereda prueba; B17 400/430 g; B20 unknown',
    () async {
      final tester = _Pump();
      await open(tester);
      expect(controller.capture, isNull);
      expect(controller.canAccept, isFalse);
      await read(tester, weight(400));
      expect(controller.capture!.totalMinor, 2000);
      expect(
        service.active!.snapshot.measurement!.stability,
        ScaleStability.unknown,
      );
      await read(tester, weight(430));
      expect(controller.capture!.totalMinor, 2150);
      await read(tester, weight(0));
      expect(controller.canAccept, isFalse);
      expect(controller.capture, isNull);
      final stopping = controller.stop();
      await tester.pump();
      expect(await stopping, isTrue);
      controller.start();
      await tester.pump();
      expect(controller.capture, isNull);
      expect(controller.canAccept, isFalse);
      await close(tester);
    },
  );

  test(
    'B18 referencia real 100 g; B21/B22 aceptación presentada e inmutable',
    () async {
      final tester = _Pump();
      await open(
        tester,
        catalog: conditions(price: 1200, reference: 100, code: 'g'),
      );
      await read(tester, weight(150));
      expect(controller.capture!.totalMinor, 1800);
      final oldRevision = controller.revision;
      expect(controller.accept(oldRevision), isNull);
      controller.presented(oldRevision);
      await read(tester, weight(160));
      expect(controller.accept(oldRevision), isNull);
      controller.presented(controller.revision);
      final result = controller.accept(controller.revision)!;
      expect(result.measuredQuantity, '160');
      expect(result.displayQuantity, '160');
      expect(result.targetAmountMinor, isNull);
      final command = result.toCommand('variant');
      expect(command.expectedUnitId, 'g');
      expect(command.expectedUnitPriceMinor, 1200);
      expect(command.expectedPriceReferenceQuantityAtomic, 100);
      expect(
        const MeasuredSaleCalculator().totalMinor(
          unitPriceMinor: command.expectedUnitPriceMinor!,
          quantityAtomic: 160,
          priceReferenceQuantityAtomic:
              command.expectedPriceReferenceQuantityAtomic!,
        ),
        1920,
      );
      expect(controller.accept(controller.revision), isNull);
      expect(result.measuredQuantity, '160');
      await close(tester);
    },
  );

  for (final failure in [
    ScaleFailure.nonPositive,
    ScaleFailure.invalidFrame,
    ScaleFailure.unsupportedUnit,
    ScaleFailure.unrepresentableWeight,
    ScaleFailure.overflow,
    ScaleFailure.transportError,
  ]) {
    test('B19 invalida positivo ante $failure', () async {
      final tester = _Pump();
      await open(tester);
      await read(tester, weight(400));
      controller.presented(controller.revision);
      await read(tester, ScaleMeasurement(failure: failure));
      expect(controller.capture, isNull);
      expect(controller.error, isNotNull);
      expect(controller.accept(controller.revision), isNull);
      await close(tester);
    });
  }

  for (final value in [-1, 0, 9007199254740992]) {
    test('B19 rechaza gramos $value sin redondeo', () async {
      final tester = _Pump();
      await open(tester);
      await read(tester, weight(value));
      expect(controller.canAccept, isFalse);
      expect(controller.error, isNotNull);
      await close(tester);
    });
  }

  test('B19 subgramo y overflow monetario no dejan importe', () async {
    final tester = _Pump();
    await open(
      tester,
      catalog: conditions(
        price: MeasuredSaleCalculator.maxInteger,
        reference: 1,
      ),
    );
    await read(
      tester,
      ScaleMeasurement(
        weight: ScaleWeight(
          coefficient: BigInt.from(4),
          decimalPlaces: 4,
          unit: ScaleUnit.kg,
          grams: 1,
        ),
      ),
    );
    expect(controller.error, contains('fracción de gramo'));
    expect(controller.canAccept, isFalse);
    await read(tester, weight(2));
    expect(controller.error, contains('importe excede'));
    expect(controller.capture, isNull);
    await close(tester);
  });

  test('B05/B19 reloj al aceptar y temporizador sin nueva trama', () async {
    final tester = _Pump();
    await open(tester);
    await read(tester, weight(400));
    controller.presented(controller.revision);
    now = const Duration(seconds: 2);
    expect(controller.accept(controller.revision), isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(controller.capture, isNull);
    expect(controller.error, contains('vencida'));
    await close(tester);
  });

  test('B25 acumulación observable redondea línea completa', () async {
    final tester = _Pump();
    final catalog = conditions(price: 1, reference: 3, code: 'g');
    await open(tester, catalog: catalog);
    await read(tester, weight(1));
    expect(controller.capture!.totalMinor, 0);
    drafts.add(draftWith(const MeasuredSalePreview().capture(catalog, 1)));
    await tester.pump();
    expect(controller.accumulated!.totalMinor, 1);
    controller.presented(controller.revision);
    drafts.addError(StateError('draft unavailable'));
    await tester.pump();
    expect(controller.canAccept, isFalse);
    await close(tester);
  });

  test(
    'B23 cierre pendiente/fallido conserva propiedad y permite reintentar',
    () async {
      final tester = _Pump();
      await open(tester);
      gateway.failClose = true;
      final stopping = controller.stop();
      expect(controller.capture, isNull);
      expect(controller.canAccept, isFalse);
      expect(service.active!.owner, ScaleSessionOwner.sale);
      gateway.reads.last.complete([weight(400)]);
      await tester.pump();
      expect(await stopping, isFalse);
      expect(service.active, isNotNull);
      gateway.failClose = false;
      expect(await controller.stop(), isTrue);
      expect(service.active, isNull);
      await close(tester);
    },
  );
}

class _Pump {
  Future<void> pump([Duration duration = Duration.zero]) =>
      Future<void>.delayed(duration);
}
