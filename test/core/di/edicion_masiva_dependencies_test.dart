import 'package:pos_flutter/application/sync/sync_capability_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/edicion_masiva/catalogo_edicion_masiva.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/controlador_edicion_masiva.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directorio;
  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('pos-s5-di-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directorio.path,
        );
  });
  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) await getIt<AppDatabase>().close();
    if (getIt.isRegistered<AppConfigController>()) {
      await getIt<AppConfigController>().dispose();
    }
    await getIt.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directorio.delete(recursive: true);
  });
  for (final modo in AppMode.values) {
    test(
      'M39/M41/M42: DI pública comparte base y diario en ${modo.name}, sin transporte',
      () async {
        var conexiones = 0;
        await HttpOverrides.runZoned(
          () async {
            final config = AppConfig.initial.copyWith(
              mode: modo,
              setupCompleted: true,
              backupProvider: BackupProvider.none,
            );
            await AppConfigFileStore().saveConfig(config);
            await setupDependencyInjection();
            await getIt<SyncCapabilityStore>().write(
              getIt<SyncEndpointConfig>().baseUrl,
              ['offer_pricing_v2'],
            );
            if (modo == AppMode.standalone) {
              await startConfiguredRuntimeServices(config);
            }
            await getIt<ProductoCommandService>().crearArticulo(
              const CrearArticuloCommand.conVariantes(
                nombre: 'Recepción DI',
                variantes: [
                  CrearArticuloVarianteCommand(
                    nombre: null,
                    precioVenta: '20',
                    costoEstandar: '10',
                    inventoryUnitId: InventoryUnitIds.piece,
                    initialStockQuantity: '5',
                  ),
                ],
              ),
            );
            final catalogo = getIt<CatalogoEdicionMasiva>();
            final comando = getIt<EdicionMasivaCommandService>();
            final fila = (await catalogo.buscar()).single;
            final c = ControladorEdicionMasiva(
              catalogo: catalogo,
              comando: comando,
            );
            try {
              await c.editarCosto(fila.clave, '12');
              await c.editarCantidad(fila.clave, '3');
              final resultados = await c.guardar(await c.prepararRevision());
              expect(resultados.single.aplicada, isTrue);
              final actual = (await catalogo.leer({
                fila.clave,
              })).filas[fila.clave]!;
              expect(actual.ventaMinor, 2000);
              expect(actual.costoMinor, 1200);
              expect(actual.entrada!.existenciaAtomic, 8);
              expect(await comando.registros(), hasLength(1));
              final db = getIt<AppDatabase>();
              final events = await comando.eventos(
                resultados.single.resultado!,
              );
              expect(events, hasLength(2));
              expect(
                events.every(
                  (e) =>
                      e.deliveryStatus ==
                      (modo == AppMode.standalone ? 'not_required' : 'pending'),
                ),
                isTrue,
              );
              final refs = await db.select(db.eventRefs).get();
              expect(refs.isEmpty, modo == AppMode.standalone);
              final movimientos = await db.select(db.inventoryMovements).get();
              expect(
                movimientos.where((m) => m.movementType == 'stock_receipt'),
                hasLength(1),
              );
              await comando.ejecutar(
                (await comando.registros()).single.operacion,
              );
              expect(
                await db.select(db.inventoryMovements).get(),
                hasLength(movimientos.length),
              );
            } finally {
              c.dispose();
            }
            if (modo == AppMode.standalone) {
              await stopConfiguredRuntimeServices(config);
            }
          },
          createHttpClient: (_) {
            conexiones++;
            throw StateError('Esta prueba no admite transporte remoto.');
          },
        );
        expect(conexiones, 0);
      },
    );
  }
}
