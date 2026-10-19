import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../application/commands/inventario/inventory_command_service.dart';
import '../../../application/commands/local_command_context.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/edicion_masiva/diario_edicion_masiva.dart';
import '../../../application/edicion_masiva/operacion_edicion_masiva.dart';
import '../../../application/edicion_masiva/registro_operacion_masiva.dart';
import '../../../application/edicion_masiva/resultado_operacion_masiva.dart';
import '../../../application/edicion_masiva/unidad_trabajo_masiva.dart';
import '../../../application/sync/event_processor.dart';
import '../../../application/sync/handlers/inventory_event_handler.dart';
import '../../../application/sync/handlers/producto_event_handler.dart';
import '../../../application/sync/payloads/movimiento_inventario_registrado_payload.dart';
import '../../../application/sync/payloads/producto_actualizado_payload.dart';
import '../../repositories/drift_catalogo_edicion_masiva.dart';
import '../../repositories/unidad_inventario_repository_impl.dart';
import 'app_database.dart';
import 'drift_categoria_projection_store.dart';
import 'drift_inventory_projection_store.dart';
import 'drift_local_event_store.dart';
import 'drift_producto_projection_store.dart';
import 'drift_proveedor_projection_store.dart';
import 'drift_sync_persistence.dart';
import 'drift_variant_inventory_memory_store.dart';

/// Compone comandos, handlers, lecturas y diario con la MISMA instancia de db.
/// Las transacciones interiores de comandos/eventos son savepoints de esta
/// transacción exterior. No admite almacenes arbitrarios ni fallback serial.
class DriftDiarioEdicionMasiva implements DiarioEdicionMasiva {
  DriftDiarioEdicionMasiva({
    required AppDatabase db,
    required AppConfigController config,
    required LocalCommandContext context,
  }) : _db = db,
       _config = config {
    final inventory = DriftInventoryProjectionStore(
      inventoryDao: db.inventoryDao,
      unitDao: db.unitDao,
    );
    final products = DriftProductoProjectionStore(productoDao: db.productoDao);
    final suppliers = DriftProveedorProjectionStore(db.proveedorDao);
    final memory = DriftVariantInventoryMemoryStore(
      dao: db.variantInventoryMemoryDao,
    );
    _history = DriftSyncPersistence(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      syncCheckpointDao: db.syncCheckpointDao,
    );
    final handler = ProductoEventHandler(
      products,
      variantInventoryMemoryStore: memory,
      inventoryProjectionStore: inventory,
      proveedorProjectionStore: suppliers,
    );
    final events = DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      appConfigController: config,
      eventProcessor: EventProcessor(
        handlers: {
          ProductoActualizadoPayload.eventType:
              handler.applyProductoActualizado,
          MovimientoInventarioRegistradoPayload.eventType:
              InventoryEventHandler(
                inventory,
              ).applyMovimientoInventarioRegistrado,
        },
      ),
    );
    _products = ProductoCommandService(
      eventStore: events,
      commandContext: context,
      categoriaProjectionStore: DriftCategoriaProjectionStore(
        categoriaDao: db.categoriaDao,
      ),
      syncedEventHistory: _history,
      unidadInventarioRepository: UnidadInventarioRepositoryImpl(
        unitDao: db.unitDao,
      ),
      inventoryProjectionStore: inventory,
      productoProjectionStore: products,
      proveedorProjectionStore: suppliers,
    );
    _inventory = InventoryCommandService(
      eventStore: events,
      commandContext: context,
      inventoryProjectionStore: inventory,
      history: _history,
    );
  }

  final AppDatabase _db;
  final AppConfigController _config;
  late final DriftSyncPersistence _history;
  late final ProductoCommandService _products;
  late final InventoryCommandService _inventory;

  @override
  Future<T> transaccion<T>(
    Future<T> Function(UnidadTrabajoMasiva unidad) action,
  ) => _db.transaction(() async {
    final modo = _config.mode;
    final result = await action(
      UnidadTrabajoMasiva(
        modo: modo,
        catalogo: DriftCatalogoEdicionMasiva(_db),
        productos: _products,
        inventario: _inventory,
        historial: _history,
      ),
    );
    if (_config.mode != modo) {
      throw StateError('El modo cambió durante la operación.');
    }
    return result;
  });

  @override
  Future<RegistroOperacionMasiva?> buscar(String operationId) async {
    final row = await _db.bulkEditOperationDao.buscar(operationId);
    return row == null ? null : _registro(row);
  }

  @override
  Future<List<RegistroOperacionMasiva>> listar({
    String? batchId,
    bool soloPendientes = false,
  }) async => (await _db.bulkEditOperationDao.listar(
    batchId: batchId,
    soloPendientes: soloPendientes,
  )).map(_registro).toList(growable: false);

  @override
  Future<void> reservar(OperacionEdicionMasiva operacion) =>
      _db.transaction(() async {
        final anterior = await buscar(operacion.operationId);
        if (anterior != null) {
          if (anterior.operacion.intencionJson != operacion.intencionJson) {
            throw StateError('Identidad reutilizada con otra intención.');
          }
          return;
        }
        if (_config.mode != operacion.modo) {
          throw StateError('La captura pertenece a otro modo.');
        }
        await _db.bulkEditOperationDao.reservar(
          BulkEditOperationsCompanion.insert(
            operationId: operacion.operationId,
            batchId: operacion.batchId,
            productId: operacion.productId,
            mode: operacion.modo.storageValue,
            intentJson: operacion.intencionJson,
            localState: 'confirmada',
            confirmedAt: DateTime.now().toUtc(),
          ),
        );
      });

  @override
  Future<void> completar(ResultadoOperacionMasiva resultado) async {
    if (await _db.bulkEditOperationDao.completar(
          resultado.operationId,
          resultado.json,
        ) !=
        1) {
      throw StateError('La operación ya no está confirmada.');
    }
  }

  @override
  Future<void> cerrarPendientes(String batchId) async {
    await _db.bulkEditOperationDao.cerrarPendientes(batchId);
  }

  RegistroOperacionMasiva _registro(BulkEditOperationRow row) {
    final op = OperacionEdicionMasiva.fromJson(row.intentJson);
    if (op.operationId != row.operationId ||
        op.batchId != row.batchId ||
        op.productId != row.productId ||
        op.modo.storageValue != row.mode) {
      throw StateError('El diario contiene una identidad inconsistente.');
    }
    return RegistroOperacionMasiva(
      operacion: op,
      estado: EstadoOperacionMasiva.values.byName(row.localState),
      resultado: row.resultJson == null
          ? null
          : ResultadoOperacionMasiva.fromJson(row.resultJson!),
      confirmadaAt: row.confirmedAt,
      finalizadaAt: row.finishedAt,
    );
  }
}
