import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import '../../support/product_supplier_harness.dart';

void main() {
  test(
    'servidor previo sin capability recibe health y ningún proveedor/precio',
    () async {
      final h = ProductSupplierHarness(mode: AppMode.serverSync);
      addTearDown(h.dispose);
      final sid = await h.supplier('Offline');
      await h.commands.crearArticulo(
        CrearArticuloCommand.conVariantes(
          nombre: 'Producto',
          variantes: [
            CrearArticuloVarianteCommand.conProveedores(
              nombre: null,
              precioVenta: '10',
              costoEstandar: null,
              proveedores: [
                ProveedorVariante(
                  proveedorId: sid,
                  precioInformadoMenor: 0,
                  fechaInformadaMs: 1000,
                ),
              ],
            ),
          ],
        ),
      );
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'ok',
            'latest_server_sequence': 0,
            'server_time': DateTime.now().toIso8601String(),
          }),
        );
        await request.response.close();
      });
      await expectLater(
        h.tracking.push('http://127.0.0.1:${server.port}').pushPendingEvents(),
        throwsException,
      );
      expect(requests, ['GET /sync/health']);
      expect(await h.tracking.history.pendingEvents(), hasLength(2));
      expect(await h.db.select(h.db.variantSuppliers).get(), hasLength(1));
    },
  );

  test(
    'tipo desconocido también falla en un eco y conserva checkpoint',
    () async {
      final h = ProductSupplierHarness(mode: AppMode.serverSync);
      addTearDown(h.dispose);
      await h.supplier('Optimista');
      final e = (await h.tracking.storedEvents()).single;
      await expectLater(
        h.tracking.remote.applySyncedEvents(
          [e.copyWith(eventType: 'future_supplier_event', serverSequence: 2)],
          afterApply: () =>
              h.tracking.history.updateLastFullPullServerSequence(2),
        ),
        throwsUnsupportedError,
      );
      expect(await h.tracking.history.lastFullPullServerSequence(), 0);
      expect(
        (await h.tracking.storedEvents()).single.deliveryStatus,
        'pending',
      );
    },
  );

  test(
    'fallo de aplicación revierte página, catálogo y cursor; reintento válido aplica todo',
    () async {
      final source = ProductSupplierHarness(mode: AppMode.serverSync),
          target = ProductSupplierHarness(mode: AppMode.serverSync);
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      await source.supplier('Oficial');
      final root = (await source.tracking.storedEvents()).single.copyWith(
        serverSequence: 1,
        deliveryStatus: 'delivered',
      );
      final update = root.copyWith(
        eventId: '00000000-0000-4000-8000-000000000999',
        eventType: ProveedorActualizadoPayload.eventType,
        serverSequence: 2,
        baseVersion: 2,
        payload: ProveedorActualizadoPayload(
          baseEventId: root.eventId,
          before: ProveedorCreadoPayload(name: 'Oficial'),
          after: ProveedorCreadoPayload(name: 'Editado'),
        ).toJson(),
      );
      await expectLater(
        target.tracking.remote.applySyncedEvents(
          [root, update],
          afterApply: () =>
              target.tracking.history.updateLastFullPullServerSequence(2),
        ),
        throwsStateError,
      );
      expect(await target.tracking.history.lastFullPullServerSequence(), 0);
      expect(await target.db.select(target.db.suppliers).get(), isEmpty);
      expect(await target.db.select(target.db.events).get(), isEmpty);
      await target.tracking.remote.applySyncedEvents(
        [root, update.copyWith(baseVersion: 1)],
        afterApply: () =>
            target.tracking.history.updateLastFullPullServerSequence(2),
      );
      expect(
        (await target.db.select(target.db.suppliers).get()).single.name,
        'Editado',
      );
      expect(await target.tracking.history.lastFullPullServerSequence(), 2);
    },
  );

  test('cambiar modo no importa proveedor ni artículo standalone', () async {
    final h = ProductSupplierHarness();
    addTearDown(h.dispose);
    final sid = await h.supplier('Local');
    h.tracking.config.update(
      h.tracking.config.config.copyWith(mode: AppMode.serverSync),
    );
    await expectLater(
      h.commands.crearArticulo(
        CrearArticuloCommand.conVariantes(
          nombre: 'No importar',
          variantes: [
            CrearArticuloVarianteCommand.conProveedores(
              nombre: null,
              precioVenta: '10',
              costoEstandar: null,
              proveedores: [
                ProveedorVariante(
                  proveedorId: sid,
                  precioInformadoMenor: 0,
                  fechaInformadaMs: 1000,
                ),
              ],
            ),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await h.tracking.history.pendingEvents(), isEmpty);
    expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    expect(
      (await h.tracking.storedEvents()).single.deliveryStatus,
      'not_required',
    );
  });
}
