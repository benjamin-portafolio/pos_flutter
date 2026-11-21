import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_replenishment_patch.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  for (final mode in AppMode.values) {
    test(
      '${mode.name}: masiva borrador/revisión/base/reintento conserva omitidas sin stock',
      () async {
        final h = ProductSupplierHarness(mode: mode);
        try {
          final rows = await seedRecepcion(h, medido: true);
          final row = rows.firstWhere((r) => r.nombreVariante == 'Piezas');
          final omitted = rows.firstWhere((r) => r.nombreVariante == 'Peso');
          final before = await h.tracking.products.snapshot(
            row.clave.productId,
          );
          final stock = await h.db.select(h.db.inventoryBalances).get();
          final movements = await h.db.select(h.db.inventoryMovements).get();
          final draft = BorradorEdicionMasiva(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
          );
          await draft.editarReposicion(
            row.clave,
            SupplierReplenishmentPatch.fromJson({
              'target_stock_atomic': 1500,
              'current_supplier_id': null,
            }),
          );
          final review = await draft.prepararRevision();
          expect(review.cambios, hasLength(1));
          final service = coordinadorRecepcion(h);
          final op = (await service.confirmar(
            batchId: 's2-config',
            cambios: review.cambios,
          )).single;
          final recovered = OperacionEdicionMasiva.fromJson(op.intencionJson);
          expect(recovered.intencionJson, op.intencionJson);
          final reopened = BorradorEdicionMasiva(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
          );
          await reopened.recuperar([recovered]);
          expect(
            (await reopened.prepararRevision())
                .cambios
                .single
                .replenishment
                .targetAtomic,
            1500,
          );
          final result = await service.ejecutar(recovered);
          expect((await service.ejecutar(recovered)).json, result.json);
          final after = await h.tracking.products.snapshot(row.clave.productId);
          expect(
            after.variantes
                .firstWhere((v) => v.id == row.clave.variantId)
                .replenishment
                .targetAtomic,
            1500,
          );
          expect(
            after.variantes
                .firstWhere((v) => v.id == omitted.clave.variantId)
                .toJson(),
            before.variantes
                .firstWhere((v) => v.id == omitted.clave.variantId)
                .toJson(),
          );
          expect(await h.db.select(h.db.inventoryBalances).get(), stock);
          expect(await h.db.select(h.db.inventoryMovements).get(), movements);
          // Original captured bases cannot be reused as a new operation.
          final stale = (await service.confirmar(
            batchId: 's2-stale',
            cambios: review.cambios,
          )).single;
          await expectLater(service.ejecutar(stale), throwsStateError);
          final invalid = BorradorEdicionMasiva(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
          );
          await invalid.editarReposicion(
            row.clave,
            SupplierReplenishmentPatch.fromJson({
              'current_supplier_id': 'aaaaaaaa-0000-4000-8000-000000000001',
            }),
          );
          expect(
            (await invalid.prepararRevision()).filas.single.errores,
            isNotEmpty,
          );
          // Recovered changes retain explicit clear, rather than converting it to preserve.
          final clear = CambioVarianteMasiva(
            clave: row.clave,
            baseProducto: (await releerRecepcion(h.db, row.clave)).baseProducto,
            replenishment: SupplierReplenishmentPatch.fromJson({
              'target_stock_atomic': null,
            }),
            venta: const CambioExplicito.conservar(),
            costo: const CambioExplicito.conservar(),
            precioProveedor: null,
            entrada: null,
          );
          final clearOp = (await service.confirmar(
            batchId: 's2-clear',
            cambios: [clear],
          )).single;
          await service.ejecutar(clearOp);
          expect(
            (await h.tracking.products.snapshot(row.clave.productId)).variantes
                .firstWhere((v) => v.id == row.clave.variantId)
                .replenishment
                .targetAtomic,
            isNull,
          );
        } finally {
          await h.dispose();
        }
      },
    );
  }
}
