import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  for (final mode in AppMode.values) {
    test(
      'oferta masiva rollback SQL y reintento exacto en ${mode.name}',
      () async {
        final h = ProductSupplierHarness(mode: mode);
        addTearDown(h.dispose);
        final rows = await seedRecepcion(h);
        final key = rows.first.clave;
        final draft = BorradorEdicionMasiva(
          catalogo: DriftCatalogoEdicionMasiva(h.db),
        );
        await draft.editarOferta(key, const CambioExplicito.establecer('11'));
        final service = coordinadorRecepcion(h);
        final operation = (await service.confirmar(
          batchId: 'rollback-offer',
          cambios: (await draft.prepararRevision()).cambios,
        )).single;
        final before = await fotoRecepcion(h.db);
        await h.db.customStatement(
          "CREATE TRIGGER offer_rollback_probe BEFORE UPDATE ON product_variants WHEN NEW.offer_price_minor = 1100 BEGIN SELECT RAISE(ABORT, 'offer rollback probe'); END",
        );
        await expectLater(
          service.ejecutar(operation),
          throwsA(
            predicate((e) => e.toString().contains('offer rollback probe')),
          ),
        );
        expect(
          await fotoRecepcion(h.db),
          before,
          reason: 'Evento, undo, refs, proyección y diario revierten juntos.',
        );
        await h.db.customStatement('DROP TRIGGER offer_rollback_probe');
        final result = await service.ejecutar(operation);
        expect(result.catalogEventId, isNotNull);
        expect(result.entradas, isEmpty);
        expect((await releerRecepcion(h.db, key)).ofertaMinor, 1100);
        final committed = await fotoRecepcion(h.db);
        expect(committed['inventory_balances'], before['inventory_balances']);
        expect(committed['inventory_movements'], before['inventory_movements']);
        expect((await service.ejecutar(operation)).json, result.json);
        expect(await fotoRecepcion(h.db), committed);
      },
    );
  }
}
