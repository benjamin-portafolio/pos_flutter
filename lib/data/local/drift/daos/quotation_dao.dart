part of '../app_database.dart';

/// Selección durable; las consultas se invalidan también por estado y catálogo.
@DriftAccessor(tables: [Quotations, QuotationItems, Sales])
class QuotationDao extends DatabaseAccessor<AppDatabase>
    with _$QuotationDaoMixin
    implements QuotationProjectionStore {
  QuotationDao(super.db);

  JoinedSelectStatement<HasResultSet, dynamic> _documents(
    String userId,
    String deviceId,
    String? quotationId,
  ) {
    final query =
        select(quotations).join([
            leftOuterJoin(
              quotationItems,
              quotationItems.quotationId.equalsExp(quotations.id),
            ),
            leftOuterJoin(
              sales,
              sales.id.equalsExp(quotations.currentSaleId) &
                  sales.userId.equalsExp(quotations.userId) &
                  sales.deviceId.equalsExp(quotations.deviceId),
            ),
          ])
          ..where(
            quotations.userId.equals(userId) &
                quotations.deviceId.equals(deviceId) &
                quotations.active.equals(true),
          )
          ..orderBy([
            OrderingTerm.desc(quotations.issuedAtLocal),
            OrderingTerm.desc(quotations.id),
            OrderingTerm.asc(quotationItems.sortOrder),
          ]);
    if (quotationId != null) query.where(quotations.id.equals(quotationId));
    return query;
  }

  List<({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})>
  _documentRows(List<TypedResult> rows) => [
    for (final row in rows)
      (
        quotation: row.readTable(quotations),
        item: row.readTableOrNull(quotationItems),
        sale: row.readTableOrNull(sales),
      ),
  ];

  Stream<
    List<({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})>
  >
  watchDocuments(String userId, String deviceId, {String? quotationId}) =>
      // La señal incluye las dependencias de la estimación sin hacer joins que
      // dupliquen líneas (recetas) ni guardar precios en el documento.
      db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              quotations,
              quotationItems,
              sales,
              db.products,
              db.productVariants,
              db.units,
              db.recipeComponents,
            },
          )
          .watch()
          .asyncMap(
            (_) async => _documentRows(
              await _documents(userId, deviceId, quotationId).get(),
            ),
          );

  Future<
    List<({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})>
  >
  readDocument(String userId, String deviceId, String quotationId) async =>
      _documentRows(await _documents(userId, deviceId, quotationId).get());

  @override
  Future<T> atomic<T>(Future<T> Function() action) => transaction(action);

  @override
  Future<QuotationProjection?> findById(String id) async {
    final row = await (select(
      quotations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _quotation(row);
  }

  @override
  Future<QuotationProjection?> findByCurrentSaleId(String saleId) async {
    final row =
        await (select(quotations)..where(
              (t) => t.currentSaleId.equals(saleId) & t.active.equals(true),
            ))
            .getSingleOrNull();
    return row == null ? null : _quotation(row);
  }

  @override
  Future<SyncEvent?> findEventById(String eventId) async {
    final row = await db.eventDao.obtenerEventoPorId(eventId);
    if (row == null) return null;
    return SyncEvent(
      eventId: row.eventId,
      aggregateType: row.aggregateType,
      aggregateId: row.aggregateId,
      eventType: row.eventType,
      userId: row.userId,
      deviceId: row.deviceId,
      baseVersion: row.baseVersion,
      baseServerSequence: row.baseServerSequence,
      serverSequence: row.serverSequence,
      applicationStatus: row.applicationStatus,
      deliveryStatus: row.deliveryStatus,
      createdAtLocal: row.createdAtLocal,
      createdAtServer: row.createdAtServer,
      payload: (jsonDecode(row.payload) as Map).cast<String, Object?>(),
    );
  }

  QuotationProjection _quotation(QuotationRow row) => QuotationProjection(
    id: row.id,
    active: row.active,
    version: row.version,
    createdEventId: row.createdEventId,
    lastEventId: row.lastEventId,
    lastServerSequence: row.lastServerSequence,
    userId: row.userId,
    deviceId: row.deviceId,
    issuedAtLocal: row.issuedAtLocal.toUtc(),
    sourceSaleId: row.sourceSaleId,
    sourceDraftEventId: row.sourceDraftEventId,
    currentSaleId: row.currentSaleId,
  );

  @override
  Future<List<QuotationItemProjection>> items(String quotationId) async {
    final rows =
        await (select(quotationItems)
              ..where((t) => t.quotationId.equals(quotationId))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    return [
      for (final row in rows)
        QuotationItemProjection(
          id: row.id,
          active: row.active,
          version: row.version,
          createdEventId: row.createdEventId,
          lastEventId: row.lastEventId,
          lastServerSequence: row.lastServerSequence,
          quotationId: row.quotationId,
          sortOrder: row.sortOrder,
          selection: QuotationSelectionSnapshot(
            variantId: row.variantId,
            productName: row.productNameSnapshot,
            variantName: row.variantNameSnapshot,
            saleMode: row.saleModeSnapshot,
            quantity: row.quantity,
            measuredQuantityAtomic: row.measuredQuantityAtomic,
            unitCode: row.saleUnitCodeSnapshot,
            unitSymbol: row.saleUnitSymbolSnapshot,
            unitAtomicFactor: row.saleUnitAtomicFactorSnapshot,
          ),
        ),
    ];
  }

  @override
  Future<void> insertQuotation(QuotationProjection q) async {
    await into(quotations).insert(
      QuotationsCompanion.insert(
        id: q.id,
        userId: q.userId,
        deviceId: q.deviceId,
        issuedAtLocal: q.issuedAtLocal,
        sourceSaleId: q.sourceSaleId,
        sourceDraftEventId: q.sourceDraftEventId,
        currentSaleId: Value(q.currentSaleId),
        active: Value(q.active),
        version: Value(q.version),
        createdEventId: Value(q.createdEventId),
        lastEventId: Value(q.lastEventId),
        lastServerSequence: Value(q.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> insertItem(QuotationItemProjection item) async {
    final s = item.selection;
    await into(quotationItems).insert(
      QuotationItemsCompanion.insert(
        id: item.id,
        quotationId: item.quotationId,
        variantId: s.variantId,
        productNameSnapshot: s.productName,
        variantNameSnapshot: Value(s.variantName),
        saleModeSnapshot: s.saleMode,
        quantity: Value(s.quantity),
        measuredQuantityAtomic: Value(s.measuredQuantityAtomic),
        saleUnitCodeSnapshot: Value(s.unitCode),
        saleUnitSymbolSnapshot: Value(s.unitSymbol),
        saleUnitAtomicFactorSnapshot: Value(s.unitAtomicFactor),
        sortOrder: item.sortOrder,
        active: Value(item.active),
        version: Value(item.version),
        createdEventId: Value(item.createdEventId),
        lastEventId: Value(item.lastEventId),
        lastServerSequence: Value(item.lastServerSequence),
      ),
    );
  }

  @override
  Future<bool> containsSaleItem(String id) async =>
      (await (db.select(
        db.saleItems,
      )..where((t) => t.id.equals(id))).getSingleOrNull()) !=
      null;

  @override
  Future<void> linkRecoveredSale({
    required String quotationId,
    required int baseVersion,
    required String baseEventId,
    required String? previousSaleId,
    required String saleId,
    required String eventId,
  }) async {
    final count =
        await (update(quotations)..where(
              (t) =>
                  t.id.equals(quotationId) &
                  t.active.equals(true) &
                  t.version.equals(baseVersion) &
                  t.lastEventId.equals(baseEventId) &
                  (previousSaleId == null
                      ? t.currentSaleId.isNull()
                      : t.currentSaleId.equals(previousSaleId)),
            ))
            .write(
              QuotationsCompanion(
                currentSaleId: Value(saleId),
                version: Value(baseVersion + 1),
                lastEventId: Value(eventId),
              ),
            );
    if (count != 1) throw StateError('La cotización cambió al recuperar.');
  }
}
