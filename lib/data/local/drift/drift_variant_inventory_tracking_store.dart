import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/recurso_inventario_descartado_payload.dart';
import '../../../application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'drift_producto_projection_store.dart';
import '../../../application/sync/projections/variant_inventory_tracking_store.dart';
import 'app_database.dart' as local;

/// Adaptador Drift del puerto de seguimiento de existencias.
///
/// Concentra las lecturas que el contrato necesita para resolver un recurso y
/// para decidir si es descartable. Vive en `data` para que los command services
/// y la presentación consulten este puerto y nunca las tablas directamente.
class DriftVariantInventoryTrackingStore
    implements VariantInventoryTrackingStore {
  DriftVariantInventoryTrackingStore({
    required local.InventoryDao inventoryDao,
    required local.ProductoDao productoDao,
  }) : _inventoryDao = inventoryDao,
       _productoDao = productoDao;

  final local.InventoryDao _inventoryDao;
  final local.ProductoDao _productoDao;

  @override
  Future<List<VariantTrackingResource>> resourcesByOriginVariant(
    String variantId,
  ) async {
    final rows = await _inventoryDao.obtenerRecursosPorVarianteOrigen(
      variantId,
    );
    return rows
        .map(
          (row) => VariantTrackingResource(
            id: row.id,
            name: row.name,
            defaultUnitId: row.defaultUnitId,
            originVariantId: row.originVariantId,
            active: row.active,
            version: row.version,
            createdEventId: row.createdEventId,
            lastServerSequence: row.lastServerSequence,
          ),
        )
        .toList(growable: false);
  }

  VariantTrackingResource _resource(
    local.InventoryItemRow row, {
    String? unitName,
    VariantTrackingBalance? balance,
  }) => VariantTrackingResource(
    id: row.id,
    name: row.name,
    defaultUnitId: row.defaultUnitId,
    originVariantId: row.originVariantId,
    active: row.active,
    version: row.version,
    createdEventId: row.createdEventId,
    lastServerSequence: row.lastServerSequence,
    unitName: unitName,
    balance: balance,
  );

  SyncEvent _event(local.EventRecord row) => SyncEvent.fromJson({
    ...row.toJson(),
    'payload': jsonDecode(row.payload),
    'event_id': row.eventId,
    'aggregate_type': row.aggregateType,
    'aggregate_id': row.aggregateId,
    'event_type': row.eventType,
    'device_id': row.deviceId,
    'user_id': row.userId,
    'created_at_local': row.createdAtLocal.toIso8601String(),
    'created_at_server': row.createdAtServer?.toIso8601String(),
    'local_sequence': row.localSequence,
    'server_sequence': row.serverSequence,
    'base_version': row.baseVersion,
    'base_server_sequence': row.baseServerSequence,
    'application_status': row.applicationStatus,
    'delivery_status': row.deliveryStatus,
  });

  @override
  Future<List<VariantTrackingResource>> selectionResources(
    String variantId,
  ) async {
    final db = _inventoryDao.attachedDatabase;
    final rows =
        await (db.select(db.inventoryItems)..where(
              (r) =>
                  r.originVariantId.isNull() |
                  r.originVariantId.equals(variantId),
            ))
            .get();
    final result = <VariantTrackingResource>[];
    for (final row in rows) {
      final unit = await (db.select(
        db.units,
      )..where((u) => u.unitId.equals(row.defaultUnitId))).getSingleOrNull();
      result.add(
        _resource(row, unitName: unit?.name, balance: await balanceOf(row.id)),
      );
    }
    return result;
  }

  @override
  Future<VariantTrackingHistory> historyForVariant(String variantId) async {
    final v = await _productoDao.obtenerVariantePorId(variantId);
    if (v == null) {
      return const VariantTrackingHistory(
        variantExists: false,
        createdEventId: null,
        events: [],
        currentState: null,
      );
    }
    final p = await _productoDao.obtenerProductoPorId(v.productId);
    final db = _inventoryDao.attachedDatabase;
    final rows =
        await (db.select(db.events)..where(
              (e) =>
                  e.aggregateType.equals('product') &
                  e.aggregateId.equals(v.productId) &
                  e.applicationStatus.equals('applied') &
                  e.deliveryStatus.isIn([
                    'not_required',
                    'pending',
                    'delivered',
                  ]),
            ))
            .get();
    return VariantTrackingHistory(
      variantExists: true,
      createdEventId: p?.createdEventId,
      events: rows.map(_event).toList(),
      currentState: p?.active == true
          ? await DriftProductoProjectionStore(
              productoDao: _productoDao,
            ).snapshot(v.productId)
          : null,
    );
  }

  @override
  Future<VariantTrackingDiscard?> appliedDiscard(String inventoryItemId) async {
    final row = await _inventoryDao.obtenerDescartePorRecurso(inventoryItemId);
    if (row == null) return null;
    final db = _inventoryDao.attachedDatabase;
    final stored = await (db.select(
      db.events,
    )..where((e) => e.eventId.equals(row.discardEventId))).getSingleOrNull();
    final creation =
        await (db.select(db.events)..where(
              (e) =>
                  e.aggregateId.equals(inventoryItemId) &
                  e.eventType.equals(RecursoInventarioCreadoPayload.eventType),
            ))
            .getSingleOrNull();
    if (stored == null ||
        creation == null ||
        stored.eventType != RecursoInventarioDescartadoPayload.eventType ||
        stored.aggregateId != inventoryItemId ||
        stored.applicationStatus != 'applied' ||
        stored.deliveryStatus != 'not_required' ||
        RecursoInventarioDescartadoPayload.fromJson(
              _event(stored).payload,
            ).triggerProductEventId !=
            row.triggerProductEventId) {
      throw StateError(
        'La prueba de descarte no coincide con su historial aplicado.',
      );
    }
    return VariantTrackingDiscard(
      discardEventId: row.discardEventId,
      triggerProductEventId: row.triggerProductEventId,
      event: _event(stored),
      creationEventId: creation.eventId,
    );
  }

  @override
  Future<List<SyncEvent>> unappliedInventoryEvents() async {
    final db = _inventoryDao.attachedDatabase;
    final rows =
        await (db.select(db.events)..where(
              (e) =>
                  e.applicationStatus.equals('applied').not() &
                  e.deliveryStatus.isIn([
                    'pending',
                    'not_required',
                    'delivered',
                  ]),
            ))
            .get();
    return rows.map(_event).toList();
  }

  @override
  Future<List<String>> directLinkedVariantIds(String inventoryItemId) async {
    final rows = await _productoDao.obtenerVariantesPorRecurso(inventoryItemId);
    return rows.map((row) => row.id).toList(growable: false);
  }

  @override
  Future<List<String>> recipeUsingVariantIds(String inventoryItemId) async {
    final rows = await _productoDao.obtenerVariantesConRecetaDeRecurso(
      inventoryItemId,
    );
    return rows.map((row) => row.id).toList(growable: false);
  }

  @override
  Future<VariantTrackingBalance?> balanceOf(String inventoryItemId) async {
    final row = await _inventoryDao.obtenerSaldoPorRecursoId(inventoryItemId);
    return row == null
        ? null
        : VariantTrackingBalance(
            quantityOnHandAtomic: row.quantityOnHandAtomic,
            quantityAvailableAtomic: row.quantityAvailableAtomic,
          );
  }

  @override
  Future<int> movementCount(String inventoryItemId) {
    return _inventoryDao.contarMovimientos(inventoryItemId);
  }

  @override
  Future<List<String>> unresolvedSaleIdsReferencing(String inventoryItemId) {
    return _inventoryDao.obtenerVentasPendientesConRecurso(inventoryItemId);
  }

  @override
  Future<bool> hasAppliedDiscard(String inventoryItemId) async {
    return await appliedDiscard(inventoryItemId) != null;
  }

  @override
  Future<void> discardResource({
    required String inventoryItemId,
    required String discardEventId,
    required String triggerProductEventId,
  }) {
    final db = _inventoryDao.attachedDatabase;
    return db.transaction(() async {
      await _inventoryDao.registrarDescarte(
        inventoryItemId: inventoryItemId,
        discardEventId: discardEventId,
        triggerProductEventId: triggerProductEventId,
      );
      final removed = await (db.delete(
        db.inventoryItems,
      )..where((r) => r.id.equals(inventoryItemId))).go();
      if (removed != 1) {
        throw StateError('El recurso cambió durante el descarte.');
      }
    });
  }
}
