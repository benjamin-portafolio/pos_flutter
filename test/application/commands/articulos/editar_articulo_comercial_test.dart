import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/editar_articulo_comercial_command.dart';
import 'package:pos_flutter/application/commands/articulos/editar_articulo_comercial_result.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/base_entrada_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/base_revision_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/entrada_mercancia_masiva.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_proveedor_precio.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import '../../../support/product_supplier_harness.dart';

typedef _Target = ({
  String id,
  String base,
  BaseRevisionMasiva baseRevision,
  ProductoCreadoPayload state,
});

typedef _Fixture = ({_Target target, String proveedorA, String proveedorB});

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      setUp(() => h = ProductSupplierHarness(mode: mode));
      tearDown(() => h.dispose());

      test(
        'M07/M12/M23/M24 superpone solo lo pedido en un único evento',
        () async {
          final f = await _complejo(h);
          final t = f.target;
          final v = t.state.variantes;
          final appends = h.appends.length;
          final result = await h.commands.editarArticuloComercial(
            _command(t, [
              _cambio(
                t,
                v[0],
                venta: 3000,
                costo: 999,
                pareja: ProveedorVariante(
                  proveedorId: f.proveedorA,
                  precioInformadoMenor: 1300,
                  fechaInformadaMs: 1800000000000,
                ),
              ),
              _cambio(t, v[1], costo: 500),
            ]),
          );
          expect(result, isA<EditarArticuloComercialResult>());
          expect(result.emitido, isTrue);
          expect(result.productId, t.id);
          expect(h.appends, hasLength(appends + 1));
          final event = h.appends.last.event;
          expect(event.eventId, result.eventId);
          expect(event.eventType, ProductoActualizadoPayload.eventType);
          final payload = ProductoActualizadoPayload.fromJson(event.payload);
          expect(payload.baseEventId, t.base);
          expect(payload.before.toJson(), t.state.toJson());
          expect(payload.after.nombre, t.state.nombre);
          expect(payload.after.categoriaId, t.state.categoriaId);
          expect(payload.after.saleConfiguration, t.state.saleConfiguration);
          expect(payload.after.variantes.map((x) => x.id), v.map((x) => x.id));
          expect(payload.after.variantes.map((x) => x.orden), [0, 1, 2]);

          final directa = payload.after.variantes[0];
          expect(directa.precioVentaMenor, 3000);
          expect(directa.costoEstandarMenor, 999);
          expect(directa.codigoBarras, v[0].codigoBarras);
          expect(directa.inventoryItemId, v[0].inventoryItemId);
          final parejas = {
            for (final s in directa.proveedores!) s.supplierId: s,
          };
          expect(parejas[f.proveedorA]!.quotedPriceMinor, 1300);
          expect(parejas[f.proveedorA]!.quotedAtMs, 1800000000000);
          expect(parejas[f.proveedorB]!.quotedPriceMinor, 0);
          expect(parejas[f.proveedorB]!.quotedAtMs, 1791244800000);

          final receta = payload.after.variantes[1];
          expect(receta.precioVentaMenor, v[1].precioVentaMenor);
          expect(receta.costoEstandarMenor, 500);
          expect(
            ProductoProveedorPrecio.sameList(
              receta.proveedores,
              v[1].proveedores,
            ),
            isTrue,
          );
          expect(
            receta.componentesReceta.map((c) => c.toJson()),
            v[1].componentesReceta.map((c) => c.toJson()),
          );
          expect(payload.after.variantes[2].toJson(), v[2].toJson());

          final persisted = await h.tracking.products.snapshot(t.id);
          expect(
            ProductoActualizadoPayload.sameState(persisted, payload.after),
            isTrue,
          );
          expect(persisted.variantes[0].precioVentaMenor, 3000);
          expect(persisted.variantes[1].costoEstandarMenor, 500);
        },
      );

      test('M08/M09 costo sin proveedor y venta sola conservan parejas', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        final result = await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(t, v[0], venta: 2800),
            _cambio(t, v[1], costo: 700),
          ]),
        );
        expect(result.emitido, isTrue);
        final after = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        // Venta sola: nada de costo ni de relaciones cambia.
        expect(after.variantes[0].precioVentaMenor, 2800);
        expect(after.variantes[0].costoEstandarMenor, v[0].costoEstandarMenor);
        expect(
          ProductoProveedorPrecio.sameList(
            after.variantes[0].proveedores,
            v[0].proveedores,
          ),
          isTrue,
        );
        // Costo sin proveedor: cambia el estándar y se conservan precios/fechas.
        expect(after.variantes[1].costoEstandarMenor, 700);
        expect(
          ProductoProveedorPrecio.sameList(
            after.variantes[1].proveedores,
            v[1].proveedores,
          ),
          isTrue,
        );
      });

      test('M13 estándar igual con pareja distinta o nueva no es no-op', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        // Estándar idéntico, pero el precio de la pareja cambia.
        final result = await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(
              t,
              v[0],
              costo: v[0].costoEstandarMenor,
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 4242,
                fechaInformadaMs: 1800000000000,
              ),
            ),
          ]),
        );
        expect(result.emitido, isTrue);
        final after = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        expect(after.variantes[0].costoEstandarMenor, v[0].costoEstandarMenor);
        final parejas = {
          for (final s in after.variantes[0].proveedores!) s.supplierId: s,
        };
        expect(parejas[f.proveedorA]!.quotedPriceMinor, 4242);
        expect(parejas[f.proveedorB]!.quotedPriceMinor, 0);

        // Pareja inexistente en la variante: se incorpora sin tocar el estándar.
        final t2 = await _leer(h, t.id);
        final result2 = await h.commands.editarArticuloComercial(
          _command(t2, [
            _cambio(
              t2,
              t2.state.variantes[1],
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 1200,
                fechaInformadaMs: 1800000001000,
              ),
            ),
          ]),
        );
        expect(result2.emitido, isTrue);
        final after2 = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        final receta = {
          for (final s in after2.variantes[1].proveedores!) s.supplierId: s,
        };
        expect(receta[f.proveedorB]!.quotedPriceMinor, 1500);
        expect(receta[f.proveedorA]!.quotedPriceMinor, 1200);
        expect(after2.variantes[1].costoEstandarMenor, isNull);
      });

      test('M14 precio idéntico conserva fecha; nuevo usa fecha UTC', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        // Venta cambia (emite) y la pareja trae el mismo precio con otra fecha.
        await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(
              t,
              v[0],
              venta: 2600,
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 1299,
                fechaInformadaMs: 1900000000000,
              ),
            ),
          ]),
        );
        final after = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        final pareja = after.variantes[0].proveedores!.singleWhere(
          (s) => s.supplierId == f.proveedorA,
        );
        expect(pareja.quotedPriceMinor, 1299);
        expect(pareja.quotedAtMs, 1791331200000);

        // Precio nuevo: usa la fecha informada tal cual (ya en UTC).
        final t2 = await _leer(h, t.id);
        await h.commands.editarArticuloComercial(
          _command(t2, [
            _cambio(
              t2,
              t2.state.variantes[0],
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 1350,
                fechaInformadaMs: 1800000000000,
              ),
            ),
          ]),
        );
        final after2 = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        final pareja2 = after2.variantes[0].proveedores!.singleWhere(
          (s) => s.supplierId == f.proveedorA,
        );
        expect(pareja2.quotedPriceMinor, 1350);
        expect(pareja2.quotedAtMs, 1800000000000);

        // Releer la proyección no modifica fechas.
        final persisted = await h.tracking.products.snapshot(t.id);
        expect(
          persisted.variantes[0].proveedores!
              .singleWhere((s) => s.supplierId == f.proveedorA)
              .quotedAtMs,
          1800000000000,
        );
      });

      test('M05 costo cero válido y venta cero rechazada', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        // Venta cero no es un importe válido; la transacción no escribe.
        final before = await _databaseState(h.db);
        final appends = h.appends.length;
        await expectLater(
          h.commands.editarArticuloComercial(
            _command(t, [_cambio(t, v[0], venta: 0)]),
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(h.appends, hasLength(appends));
        expect(await _databaseState(h.db), before);
        // Costo cero es un importe explícito y se persiste.
        await h.commands.editarArticuloComercial(
          _command(t, [_cambio(t, v[0], costo: 0)]),
        );
        final after = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        expect(after.variantes[0].costoEstandarMenor, 0);
        // Costo desconocido omitido se conserva.
        expect(after.variantes[1].costoEstandarMenor, isNull);
      });

      test('M25 estado idéntico o solo entrada no emite nada', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        final before = await _databaseState(h.db);
        final appends = h.appends.length;
        final result = await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(
              t,
              v[0],
              venta: v[0].precioVentaMenor,
              costo: v[0].costoEstandarMenor,
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 1299,
                fechaInformadaMs: 1900000000000,
              ),
            ),
          ]),
        );
        expect(result.emitido, isFalse);
        expect(result.eventId, isNull);
        expect(result.productId, t.id);
        expect(h.appends, hasLength(appends));
        expect(await _databaseState(h.db), before);
        expect(
          (await h.tracking.products.findProductById(t.id))!.version,
          t.baseRevision.version,
        );

        final unidad = (await UnidadInventarioRepositoryImpl(
          unitDao: h.db.unitDao,
        ).obtenerUnidadPorId(InventoryUnitIds.piece))!;
        final entrada = EntradaMercanciaMasiva(
          base: BaseEntradaMasiva(
            recurso: t.baseRevision,
            unidad: unidad,
            saldoVersion: 1,
            saldoEventId: 'saldo',
            saldoServerSequence: null,
            existenciaAtomic: 4,
            disponibleAtomic: 4,
          ),
          cantidadAtomic: 3,
        );
        final soloEntrada = await h.commands.editarArticuloComercial(
          _command(t, [_cambio(t, v[0], entrada: entrada)]),
        );
        expect(soloEntrada.emitido, isFalse);
        expect(await _databaseState(h.db), before);
      });

      test('M15 conserva legado, conocido vacío y poblado', () async {
        // Poblado: editar venta no toca parejas.
        final f = await _complejo(h);
        await h.commands.editarArticuloComercial(
          _command(f.target, [_cambio(f.target, f.target.state.variantes[0], venta: 2100)]),
        );
        final poblado = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        );
        expect(poblado.before.variantes.first.proveedores, isNotEmpty);
        expect(
          ProductoProveedorPrecio.sameList(
            poblado.after.variantes.first.proveedores,
            poblado.before.variantes.first.proveedores,
          ),
          isTrue,
        );

        // Legado desconocido: editar solo venta conserva null en ambos estados.
        final legacyId = '00000000-0000-4000-8000-0000000000aa';
        final legacyPayload = ProductoCreadoPayload.simple(
          nombre: 'Legado',
          categoriaId: null,
          varianteId: '00000000-0000-4000-8000-0000000000bb',
          precioVentaMenor: 100,
        );
        await h.local.appendAndApply(
          h.appends.last.event.copyWith(
            eventId: 'legacy-event',
            aggregateId: legacyId,
            aggregateType: ProductoCreadoPayload.aggregateType,
            eventType: ProductoCreadoPayload.eventType,
            payload: legacyPayload.toJson(),
          ),
          refs: [
            LocalEventRef.affects(refType: 'product', refId: legacyId),
          ],
        );
        final legacy = await _leer(h, legacyId);
        expect(legacy.state.variantes.first.proveedores, isNull);
        await h.commands.editarArticuloComercial(
          _command(legacy, [
            CambioVarianteMasiva(
              clave: ClaveVariante(legacy.id, legacy.state.variantes.first.id),
              baseProducto: legacy.baseRevision,
              venta: const CambioExplicito.establecer(150),
              costo: const CambioExplicito.conservar(),
              precioProveedor: null,
              entrada: null,
            ),
          ]),
        );
        final legado = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        );
        expect(legado.before.variantes.first.proveedores, isNull);
        expect(legado.after.variantes.first.proveedores, isNull);
        expect(
          h.appends.last.refs.any((r) => r.refType == 'variant_suppliers'),
          isFalse,
        );

        // Legado + pareja explícita: transición válida de null a conjunto conocido.
        final legacy2 = await _leer(h, legacyId);
        final resultado = await h.commands.editarArticuloComercial(
          _command(legacy2, [
            _cambio(
              legacy2,
              legacy2.state.variantes.first,
              pareja: ProveedorVariante(
                proveedorId: f.proveedorA,
                precioInformadoMenor: 800,
                fechaInformadaMs: 1800000000000,
              ),
            ),
          ]),
        );
        expect(resultado.emitido, isTrue);
        final transicion = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        );
        expect(transicion.before.variantes.first.proveedores, isEmpty);
        expect(transicion.after.variantes.first.proveedores, hasLength(1));
        expect(
          transicion.after.variantes.first.proveedores!.single.supplierId,
          f.proveedorA,
        );
      });

      test('M16 medido conserva configuración y referencia', () async {
        final f = await _complejo(h, measured: true);
        final t = f.target;
        final v = t.state.variantes;
        expect(t.state.saleConfiguration, isA<MeasuredSaleConfiguration>());
        await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(
              t,
              v[0],
              venta: 3100,
              costo: 450,
              pareja: ProveedorVariante(
                proveedorId: f.proveedorB,
                precioInformadoMenor: 900,
                fechaInformadaMs: 1800000000000,
              ),
            ),
          ]),
        );
        final after = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        ).after;
        expect(after.saleConfiguration, t.state.saleConfiguration);
        expect(
          (after.saleConfiguration as MeasuredSaleConfiguration).saleUnitId,
          InventoryUnitIds.kilogram,
        );
        expect(after.variantes[0].precioVentaMenor, 3100);
        expect(after.variantes[0].costoEstandarMenor, 450);
        expect(after.variantes[1].componentesReceta, isNotEmpty);
      });

      test('M19 rechaza destinos inválidos sin escribir', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        final otro = await _crear(h);
        for (final caso in [
          'producto ausente',
          'producto inactivo',
          'variante ausente',
          'variante inactiva',
          'variante ajena',
          'pertenencia incorrecta',
          'variante repetida',
          'sin cambios',
          'base ausente',
        ]) {
          final base = await _leer(h, t.id);
          var productId = base.id;
          var variantId = base.state.variantes.first.id;
          var cambios = [_cambio(base, base.state.variantes.first, venta: 2222)];
          var baseRevision = base.baseRevision;
          switch (caso) {
            case 'producto ausente':
              productId = 'ausente';
            case 'producto inactivo':
              await (h.db.update(
                h.db.products,
              )..where((p) => p.id.equals(base.id))).write(
                const ProductsCompanion(active: Value(false)),
              );
            case 'variante ausente':
              variantId = 'ausente';
              cambios = [
                _cambioManual(base, variantId, venta: 2222),
              ];
            case 'variante inactiva':
              await (h.db.update(
                h.db.productVariants,
              )..where((x) => x.id.equals(variantId))).write(
                const ProductVariantsCompanion(active: Value(false)),
              );
            case 'variante ajena':
              variantId = otro.state.variantes.first.id;
              cambios = [_cambioManual(base, variantId, venta: 2222)];
            case 'pertenencia incorrecta':
              cambios = [
                CambioVarianteMasiva(
                  clave: ClaveVariante(otro.id, variantId),
                  baseProducto: base.baseRevision,
                  venta: const CambioExplicito.establecer(2222),
                  costo: const CambioExplicito.conservar(),
                  precioProveedor: null,
                  entrada: null,
                ),
              ];
            case 'variante repetida':
              cambios = [
                _cambio(base, base.state.variantes.first, venta: 2222),
                _cambio(base, base.state.variantes.first, venta: 2223),
              ];
            case 'sin cambios':
              cambios = [];
            case 'base ausente':
              baseRevision = BaseRevisionMasiva(
                id: base.id,
                version: base.baseRevision.version,
                eventId: null,
                serverSequence: null,
              );
          }
          final before = await _databaseState(h.db);
          final appends = h.appends.length;
          await expectLater(
            h.commands.editarArticuloComercial(
              EditarArticuloComercialCommand(
                productId: productId,
                base: baseRevision,
                cambios: cambios,
              ),
            ),
            throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
            reason: caso,
          );
          expect(h.appends, hasLength(appends), reason: caso);
          expect(await _databaseState(h.db), before, reason: caso);
          // Restaurar el producto para el siguiente caso.
          await (h.db.update(h.db.products)..where((p) => p.id.equals(t.id)))
              .write(const ProductsCompanion(active: Value(true)));
          await (h.db.update(h.db.productVariants)
                ..where((x) => x.productId.equals(t.id)))
              .write(const ProductVariantsCompanion(active: Value(true)));
        }
        // Un solo cambio con venta no inválida el resto del fixture.
        expect(v.first.precioVentaMenor, 2456);
      });

      test('M20 base obsoleta rechaza sin sustituir la base viva', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        await h.commands.editarArticuloComercial(
          _command(t, [_cambio(t, v[0], venta: 2500)]),
        );
        final vigente = await h.tracking.products.findProductById(t.id);
        final before = await _databaseState(h.db);
        final appends = h.appends.length;
        await expectLater(
          h.commands.editarArticuloComercial(
            _command(t, [_cambio(t, v[0], venta: 2510)]),
          ),
          throwsStateError,
        );
        expect(h.appends, hasLength(appends));
        expect(await _databaseState(h.db), before);
        final actual = await h.tracking.products.findProductById(t.id);
        expect(actual!.version, vigente!.version);
        expect(actual.lastEventId, vigente.lastEventId);
      });

      test('refs declaradas por modo y persistidas solo en server_sync', () async {
        final f = await _complejo(h);
        final t = f.target;
        final v = t.state.variantes;
        await h.commands.editarArticuloComercial(
          _command(t, [
            _cambio(t, v[0], venta: 2700),
            _cambio(t, v[1], costo: 333),
          ]),
        );
        final event = h.appends.last.event;
        final declared = h.appends.last.refs.map(_refKey).toSet();
        expect(declared, contains('product:${t.id}:affects'));
        expect(
          declared.where((r) => r.startsWith('product_variant:')),
          hasLength(v.length),
        );
        expect(
          declared.where((r) => r.startsWith('variant_suppliers:')),
          hasLength(v.length),
        );
        expect(
          declared.where((r) => r.startsWith('supplier:')),
          hasLength(2),
        );
        expect(
          declared.where((r) => r.startsWith('inventory_item:')),
          hasLength(2),
        );
        final refs = (await h.db.select(h.db.eventRefs).get())
            .where((r) => r.eventId == event.eventId)
            .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
            .toSet();
        expect(refs, mode == AppMode.standalone ? <String>{} : declared);
        final persisted = (await h.tracking.history.eventById(event.eventId))!;
        expect(
          persisted.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(
          ProductoActualizadoPayload.fromJson(event.payload)
              .after
              .dependenciasInventario
              .every(
                (d) => (d.dependsOnEventId != null) == (mode == AppMode.serverSync),
              ),
          isTrue,
        );
        expect(
          ProductoActualizadoPayload.fromJson(event.payload)
              .after
              .dependenciasProveedores
              .every(
                (d) => (d.dependsOnEventId != null) == (mode == AppMode.serverSync),
              ),
          isTrue,
        );
      });

      if (mode == AppMode.serverSync) {
        test('M42 conserva base pendiente y la promueve al aceptarse', () async {
          final f = await _complejo(h);
          final t = f.target;
          await (h.db.update(
            h.db.events,
          )..where((e) => e.eventId.equals(t.base))).write(
            const EventsCompanion(
              deliveryStatus: Value('delivered'),
              serverSequence: Value(7),
            ),
          );
          await (h.db.update(h.db.products)..where((p) => p.id.equals(t.id)))
              .write(const ProductsCompanion(lastServerSequence: Value(7)));
          await h.commands.editarArticuloComercial(
            _command(t, [_cambio(t, t.state.variantes[0], venta: 2550)]),
          );
          expect(h.appends.last.event.baseServerSequence, 7);
          final pendiente = h.appends.last.event.eventId;
          final t2 = await _leer(h, t.id);
          await h.commands.editarArticuloComercial(
            _command(t2, [_cambio(t2, t2.state.variantes[0], venta: 2560)]),
          );
          final segundo = h.appends.last.event;
          expect(segundo.baseServerSequence, isNull);
          expect(segundo.baseVersion, 2);
          expect(
            ProductoActualizadoPayload.fromJson(segundo.payload)
                .dependencyEventIds,
            contains(pendiente),
          );
        });
      } else {
        test('M41 standalone no inicia transporte ni persiste refs', () async {
          final f = await _complejo(h);
          await h.commands.editarArticuloComercial(
            _command(f.target, [_cambio(f.target, f.target.state.variantes[0], venta: 2450)]),
          );
          expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
          expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);

          // El store valida refs aunque no las persista.
          final before = await _databaseState(h.db);
          await expectLater(
            h.local.appendAndApply(
              h.appends.last.event.copyWith(eventId: 'sin-refs'),
              refs: [],
            ),
            throwsArgumentError,
          );
          expect(await _databaseState(h.db), before);

          // Cambiar a server_sync no promueve historial local.
          h.tracking.config.update(
            h.tracking.config.config.copyWith(mode: AppMode.serverSync),
          );
          final t2 = await _leer(h, f.target.id);
          await expectLater(
            h.commands.editarArticuloComercial(
              _command(t2, [_cambio(t2, t2.state.variantes[0], venta: 2490)]),
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'motivo',
                contains('importación explícita'),
              ),
            ),
          );
          expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
        });
      }
    });
  }
}

CambioVarianteMasiva _cambio(
  _Target target,
  ProductoCreadoVariante variante, {
  int? venta,
  int? costo,
  ProveedorVariante? pareja,
  EntradaMercanciaMasiva? entrada,
}) => CambioVarianteMasiva(
  clave: ClaveVariante(target.id, variante.id),
  baseProducto: target.baseRevision,
  venta: venta == null
      ? const CambioExplicito.conservar()
      : CambioExplicito.establecer(venta),
  costo: costo == null
      ? const CambioExplicito.conservar()
      : CambioExplicito.establecer(costo),
  precioProveedor: pareja,
  entrada: entrada,
);

CambioVarianteMasiva _cambioManual(
  _Target target,
  String variantId, {
  int? venta,
}) => CambioVarianteMasiva(
  clave: ClaveVariante(target.id, variantId),
  baseProducto: target.baseRevision,
  venta: venta == null
      ? const CambioExplicito.conservar()
      : CambioExplicito.establecer(venta),
  costo: const CambioExplicito.conservar(),
  precioProveedor: null,
  entrada: null,
);

EditarArticuloComercialCommand _command(
  _Target target,
  List<CambioVarianteMasiva> cambios,
) => EditarArticuloComercialCommand(
  productId: target.id,
  base: target.baseRevision,
  cambios: cambios,
);

String _refKey(LocalEventRef ref) =>
    '${ref.refType}:${ref.refId}:${ref.relationship}';

CrearArticuloVarianteCommand _variante(String name) =>
    CrearArticuloVarianteCommand(
      nombre: name,
      precioVenta: '12.34',
      costoEstandar: '3.21',
      codigoBarras: '001',
    );

Future<_Target> _leer(ProductSupplierHarness h, String id) async {
  final product = (await h.tracking.products.findProductById(id))!;
  return (
    id: id,
    base: product.lastEventId!,
    baseRevision: BaseRevisionMasiva(
      id: product.id,
      version: product.version,
      eventId: product.lastEventId,
      serverSequence: product.lastServerSequence,
    ),
    state: await h.tracking.products.snapshot(id),
  );
}

Future<_Target> _crear(ProductSupplierHarness h) async {
  await h.commands.crearArticulo(
    CrearArticuloCommand.conVariantes(
      nombre: 'Otro',
      variantes: [_variante('Ajena')],
    ),
  );
  return _leer(h, h.appends.last.event.aggregateId);
}

Future<_Fixture> _complejo(
  ProductSupplierHarness h, {
  bool measured = false,
}) async {
  final a = await h.supplier('Proveedor A');
  final b = await h.supplier('Proveedor B');
  await h.db
      .into(h.db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: 'category',
          name: 'Preparados',
          sortOrder: 0,
          lastServerSequence: const Value(5),
        ),
      );
  await h.tracking.inventoryCommands.crearRecurso(
    const CrearRecursoInventarioCommand(
      nombre: 'Ingrediente',
      defaultUnitId: InventoryUnitIds.piece,
      quantityDeltaAtomic: 50,
    ),
  );
  final ingrediente = (await h.db.select(h.db.inventoryItems).get()).single.id;
  await h.commands.crearArticulo(
    CrearArticuloCommand.conVariantes(
      nombre: 'Producto completo',
      categoriaId: 'category',
      saleConfiguration: measured
          ? MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.kilogram,
              priceReferenceQuantityAtomic: 1000,
            )
          : const UnitSaleConfiguration(),
      variantes: [
        CrearArticuloVarianteCommand.conProveedores(
          nombre: 'Directa',
          precioVenta: '24.56',
          costoEstandar: '3.14',
          codigoBarras: '009',
          inventoryUnitId: measured
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: '4',
          proveedores: [
            ProveedorVariante(
              proveedorId: a,
              precioInformadoMenor: 1299,
              fechaInformadaMs: 1791331200000,
            ),
            ProveedorVariante(
              proveedorId: b,
              precioInformadoMenor: 0,
              fechaInformadaMs: 1791244800000,
            ),
          ],
        ),
        CrearArticuloVarianteCommand.conProveedores(
          nombre: 'Receta',
          precioVenta: '19.25',
          costoEstandar: null,
          codigoBarras: '0088',
          recipeComponents: [
            CrearArticuloRecipeComponentCommand(
              inventoryItemId: ingrediente,
              quantity: '2',
            ),
          ],
          proveedores: [
            ProveedorVariante(
              proveedorId: b,
              precioInformadoMenor: 1500,
              fechaInformadaMs: 1791158400000,
            ),
          ],
        ),
        _variante('Omitida'),
      ],
    ),
  );
  final target = await _leer(h, h.appends.last.event.aggregateId);
  return (target: target, proveedorA: a, proveedorB: b);
}

Future<Map<String, List<Map<String, Object?>>>> _databaseState(
  AppDatabase db,
) async => {
  for (final table in db.allTables)
    table.actualTableName:
        (await db
                .customSelect(
                  'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
};
