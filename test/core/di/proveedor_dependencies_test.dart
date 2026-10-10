import 'dart:io';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/proveedores/proveedor_command_service.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/projections/proveedor_projection_store.dart';
import 'package:pos_flutter/application/sync/handlers/proveedor_creado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/proveedor_actualizado_event_handler.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_supplier_di_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
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
    await directory.delete(recursive: true);
  });

  for (final mode in AppMode.values) {
    test(
      'DI real del catálogo en ${mode.name}: contratos locales y cero conexiones HTTP/WebSocket',
      () async {
        var networkCalls = 0;
        await HttpOverrides.runZoned(
          () async {
            final config = AppConfig.initial.copyWith(
              mode: mode,
              setupCompleted: true,
              backupProvider: BackupProvider.none,
            );
            await AppConfigFileStore().saveConfig(config);
            await setupDependencyInjection();
            expect(
              getIt<ProveedorDao>(),
              same(getIt<AppDatabase>().proveedorDao),
            );
            expect(getIt<ProveedorProjectionStore>(), isNotNull);
            expect(getIt<ProveedorCreadoEventHandler>(), isNotNull);
            expect(getIt<ProveedorActualizadoEventHandler>(), isNotNull);
            final service = getIt<ProveedorCommandService>();
            final repo = getIt<ProveedorRepository>();
            if (mode == AppMode.standalone) {
              await startConfiguredRuntimeServices(config);
              await service.crearProveedor(
                const CrearProveedorCommand(
                  nombre: 'Proveedor DI',
                  telefono: '001',
                ),
              );
              final base = (await repo.watchProveedores().first).single;
              await service.editarProveedor(
                EditarProveedorCommand(
                  base: base,
                  nombre: 'Proveedor editado',
                  notas: 'DI',
                ),
              );
              final current = (await repo.watchProveedores().first).single;
              expect(current.id, base.id);
              expect(current.version, 2);
              expect(current.notas, 'DI');
              final db = getIt<AppDatabase>();
              expect(await db.select(db.events).get(), hasLength(2));
              expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
              expect(await db.select(db.eventRefs).get(), isEmpty);
              expect(await db.select(db.variantSuppliers).get(), isEmpty);
              await stopConfiguredRuntimeServices(config);
            } else {
              await service.crearProveedor(
                const CrearProveedorCommand(nombre: 'Offline servidor'),
              );
              final db = getIt<AppDatabase>();
              expect(await repo.watchProveedores().first, hasLength(1));
              expect(
                (await db.select(db.events).get()).single.deliveryStatus,
                'pending',
              );
              expect(await db.select(db.eventRefs).get(), hasLength(1));
            }
          },
          createHttpClient: (_) {
            networkCalls++;
            throw StateError(
              'No se autoriza una conexión remota del catálogo.',
            );
          },
        );
        expect(networkCalls, 0);
      },
    );
  }

  test(
    'DI real: producto con proveedores standalone sin transporte remoto',
    () async {
      var networkCalls = 0;
      await HttpOverrides.runZoned(
        () async {
          final config = AppConfig.initial.copyWith(
            mode: AppMode.standalone,
            setupCompleted: true,
            backupProvider: BackupProvider.none,
          );
          await AppConfigFileStore().saveConfig(config);
          await setupDependencyInjection();
          await startConfiguredRuntimeServices(config);
          await getIt<ProveedorCommandService>().crearProveedor(
            const CrearProveedorCommand(nombre: 'Proveedor de variante'),
          );
          final supplier =
              (await getIt<ProveedorRepository>().watchProveedores().first)
                  .single;
          final products = getIt<ProductoCommandService>();
          await products.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'Producto DI',
              variantes: [
                CrearArticuloVarianteCommand.conProveedores(
                  nombre: null,
                  precioVenta: '10',
                  costoEstandar: null,
                  proveedores: [
                    ProveedorVariante(
                      proveedorId: supplier.id,
                      precioInformadoMenor: 0,
                      fechaInformadaMs: 1791331200000,
                    ),
                  ],
                ),
              ],
            ),
          );
          final db = getIt<AppDatabase>();
          final product = (await db.select(db.products).get()).single;
          final detail = (await getIt<ProductoRepository>().obtenerDetalle(
            product.id,
          ))!;
          expect(
            detail.variantes.single.proveedores!.single.proveedorId,
            supplier.id,
          );
          await products.actualizarArticulo(
            productId: product.id,
            baseEventId: product.lastEventId!,
            variantIds: [detail.variantes.single.id],
            command: const CrearArticuloCommand.conVariantes(
              nombre: 'Otro nombre',
              variantes: [
                CrearArticuloVarianteCommand(
                  nombre: null,
                  precioVenta: '15',
                  costoEstandar: '0',
                ),
              ],
            ),
          );
          expect(
            (await getIt<ProductoRepository>().obtenerDetalle(
              product.id,
            ))!.variantes.single.proveedores,
            detail.variantes.single.proveedores,
          );
          final events = await db.select(db.events).get();
          expect(events, hasLength(3));
          expect(
            events.every(
              (e) =>
                  e.deliveryStatus == 'not_required' &&
                  e.applicationStatus == 'applied',
            ),
            isTrue,
          );
          expect(await db.select(db.eventRefs).get(), isEmpty);
          expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
          await stopConfiguredRuntimeServices(config);
        },
        createHttpClient: (_) {
          networkCalls++;
          throw StateError('No se autoriza transporte remoto en esta prueba.');
        },
      );
      expect(networkCalls, 0);
    },
  );
}
