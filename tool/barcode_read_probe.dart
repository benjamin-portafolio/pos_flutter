import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/codigo_barras.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_gate.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_probe_screen.dart';

/// Entrada aislada para Android físico. No llama a main.dart, DI, servicios de
/// red ni AppDatabase(): toda la prueba vive en SQLite en memoria.
/// flutter run -d DEVICE -t tool/barcode_read_probe.dart
/// --dart-define=PROBE_CODE_A=012345678905 --dart-define=PROBE_CODE_B=7501031311309
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final clock = Stopwatch()..start();
  final gate = BarcodeReadGate(clock: () => clock.elapsed);
  final config = AppConfigController(AppConfig.initial);
  const context = LocalCommandContext(
    userId: 'barcode-probe',
    deviceId: 'probe',
  );
  final products = ProductoRepositoryImpl(productoDao: db.productoDao);
  final draft = SaleDraftRepositoryImpl(
    saleDao: db.saleDao,
    userId: context.userId,
    deviceId: context.deviceId,
  );
  final commands = VentaBorradorCommandService(
    store: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    context: context,
    events: DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      appConfigController: config,
      eventProcessor: EventProcessor(
        handlers: {
          ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
            db.saleDao,
          ).apply,
        },
      ),
    ),
  );
  final codes = {
    'A': CodigoBarras.fromInput(
      const String.fromEnvironment(
        'PROBE_CODE_A',
        defaultValue: '012345678905',
      ),
    ).value!,
    'B': CodigoBarras.fromInput(
      const String.fromEnvironment(
        'PROBE_CODE_B',
        defaultValue: '7501031311309',
      ),
    ).value!,
  };
  for (final entry in codes.entries) {
    // Fixtures exclusivas de esta base desechable, no escrituras de UI.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(id: entry.key, name: 'Prueba ${entry.key}'),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: entry.key,
            productId: entry.key,
            barcode: Value(entry.value),
            salePriceMinor: 100,
            sortOrder: 0,
          ),
        );
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Diagnóstico de escaneo')),
        body: Builder(
          builder: (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SQLite en memoria; sin datos de uso ni sincronización.',
                ),
                for (final entry in codes.entries)
                  Text('${entry.key}: ${entry.value}'),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BarcodeReadProbeScreen(
                        readGate: gate,
                        onRead: (code) async {
                          final candidates = await products
                              .buscarVariantesPorCodigoBarras(code);
                          if (candidates.isEmpty) {
                            return 'No se encontró un artículo con este código.';
                          }
                          if (candidates.length > 1) {
                            return '${candidates.length} candidatos: no se agregó ninguno.';
                          }
                          await commands.agregar(
                            AgregarProductoBorradorCommand(
                              variantId: candidates.single.varianteId,
                            ),
                          );
                          final sale = (await draft.watchCurrentDraft().first)!;
                          final result = sale.items
                              .map(
                                (item) =>
                                    '${item.productName}: ${item.quantity}',
                              )
                              .join(' · ');
                          debugPrint('Lectura aceptada $code; $result');
                          return result;
                        },
                      ),
                    ),
                  ),
                  child: const Text('Abrir lector'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
