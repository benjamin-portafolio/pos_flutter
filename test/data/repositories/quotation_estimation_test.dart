import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/prepared_quotation_line.dart';
import 'package:pos_flutter/application/sync/projections/quotation_item_projection.dart';
import 'package:pos_flutter/application/sync/quotation_recovery_validator.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/quotation_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import '../../support/quotation_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    test('P09/P10 $mode: catálogo reactivo y lectura sin escrituras', () async {
      final h = QuotationHarness(mode: mode);
      addTearDown(h.dispose);
      await h.seed();
      await h.add();
      await h.add(QuotationHarness.measuredId);
      final save = await h.intent();
      await h.service().guardar(save);
      final documents = StreamIterator(
        h.repository.watchById(save.quotationId),
      );
      addTearDown(documents.cancel);
      expect(await documents.moveNext(), isTrue);
      final selection = documents.current!.items;
      final changes = <Future<void> Function()>[
        () async {
          await (h.db.update(
            h.db.productVariants,
          )..where((t) => t.id.equals(QuotationHarness.directId))).write(
            const ProductVariantsCompanion(
              salePriceMinor: Value(12000),
              standardCostMinor: Value(1500),
            ),
          );
        },
        () async {
          await (h.db.update(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.productId)))
              .write(const ProductsCompanion(name: Value('Nombre actual')));
        },
        () async {
          await (h.db.update(h.db.recipeComponents)
                ..where((t) => t.variantId.equals(QuotationHarness.recipeId)))
              .write(const RecipeComponentsCompanion(quantityAtomic: Value(4)));
        },
        () async {
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(active: Value(false)));
        },
      ];
      for (var i = 0; i < changes.length; i++) {
        final next = documents.moveNext();
        await changes[i]();
        final beforeRead = await h.contents();
        expect(await next.timeout(const Duration(seconds: 5)), isTrue);
        final document = documents.current!;
        final estimate = await h.repository.estimate(document);
        expect(
          document.items.map((l) => l.productName),
          selection.map((l) => l.productName),
        );
        expect(estimate.lines.first.unitPriceMinor, 12000);
        if (i < 3) {
          expect(estimate.totalMinor, 19501);
        } else {
          expect(estimate.totalMinor, isNull);
          expect(estimate.lines.last.unitPriceMinor, isNull);
          expect(estimate.lines.last.totalMinor, isNull);
          expect(estimate.lines.last.issue, contains('unidad'));
        }
        expect(await h.contents(), beforeRead);
      }
    });
  }

  test(
    'P26: transacción impide mezclar revisiones del catálogo entre líneas',
    () async {
      final h = QuotationHarness();
      addTearDown(h.dispose);
      await h.seed();
      await h.add();
      await h.add(QuotationHarness.measuredId);
      final save = await h.intent();
      await h.service().guardar(save);
      final q = (await h.repository.findById(save.quotationId))!;
      final before = await h.contents(excluded: {'product_variants'});
      final validator = _PausingValidator(h.validator);
      final repository = QuotationRepositoryImpl(
        dao: h.db.quotationDao,
        validator: validator,
        userId: h.context.userId,
        deviceId: h.context.deviceId,
      );
      final estimation = repository.estimate(q);
      await validator.firstRead.future;
      var written = false;
      final write = h.db
          .update(h.db.productVariants)
          .write(const ProductVariantsCompanion(salePriceMinor: Value(20000)))
          .then((_) => written = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(written, isFalse);
      validator.resume.complete();
      final first = await estimation;
      expect(first.lines.map((l) => l.unitPriceMinor), [3500, 10001]);
      expect(first.totalMinor, 11001);
      await write;
      final second = await repository.estimate(q);
      expect(second.lines.map((l) => l.unitPriceMinor), [20000, 20000]);
      expect(second.totalMinor, 35000);
      expect(await h.contents(excluded: {'product_variants'}), before);
    },
  );
}

class _PausingValidator extends QuotationRecoveryValidator {
  _PausingValidator(QuotationRecoveryValidator source)
    : super(products: source.products, units: source.units);
  final firstRead = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<PreparedQuotationLine> prepareLine(
    QuotationItemProjection item,
  ) async {
    final line = await super.prepareLine(item);
    if (!firstRead.isCompleted) {
      firstRead.complete();
      await resume.future;
    }
    return line;
  }
}
