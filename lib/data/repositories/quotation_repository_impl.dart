import '../../domain/cotizaciones/quotation.dart';
import '../../domain/cotizaciones/quotation_estimate.dart';
import '../../domain/cotizaciones/quotation_line_estimate.dart';
import '../../application/sync/quotation_recovery_validator.dart';
import '../../application/sync/quotation_recovery_line_exception.dart';
import '../../application/sync/payloads/sale_item_snapshot.dart';
import '../../domain/cotizaciones/quotation_item.dart';
import '../../domain/cotizaciones/quotation_status.dart';
import '../../domain/repositories/quotation_repository.dart';
import '../../domain/ventas/sale_status.dart';
import '../local/drift/app_database.dart';

class QuotationRepositoryImpl implements QuotationRepository {
  QuotationRepositoryImpl({
    required this.dao,
    required this.validator,
    required this.userId,
    required this.deviceId,
  });
  final QuotationDao dao;
  final QuotationRecoveryValidator validator;
  final String userId, deviceId;

  @override
  Stream<List<Quotation>> watchQuotations({bool onlyRecoverable = true}) => dao
      .watchDocuments(userId, deviceId)
      .map(
        (rows) => _map(rows)
            .where(
              (quotation) =>
                  !onlyRecoverable ||
                  quotation.status != QuotationStatus.vendida,
            )
            .toList(),
      );

  @override
  Stream<Quotation?> watchById(String quotationId) => dao
      .watchDocuments(userId, deviceId, quotationId: quotationId)
      .map((rows) => rows.isEmpty ? null : _map(rows).single);

  @override
  Future<Quotation?> findById(String quotationId) async {
    final rows = await dao.readDocument(userId, deviceId, quotationId);
    return rows.isEmpty ? null : _map(rows).single;
  }

  @override
  Future<QuotationEstimate> estimate(
    Quotation quotation,
  ) => dao.atomic(() async {
    if (quotation.userId != userId || quotation.deviceId != deviceId) {
      throw StateError('La cotización pertenece a otro contexto.');
    }
    final lines = <QuotationLineEstimate>[];
    var sum = BigInt.zero;
    var complete = quotation.items.isNotEmpty;
    final selection = await dao.items(quotation.id);
    for (final item in quotation.items) {
      final stored = selection.where((s) => s.id == item.id).firstOrNull;
      try {
        if (stored == null) {
          throw QuotationRecoveryLineException(
            item.id,
            'La selección no está disponible.',
          );
        }
        final prepared = await validator.prepareLine(stored);
        final s = prepared.snapshot;
        sum += BigInt.from(s.totalMinor);
        lines.add(
          QuotationLineEstimate(
            quotationItemId: item.id,
            unitPriceMinor: s.unitPriceMinor,
            priceReferenceQuantityAtomic: s.priceReferenceQuantityAtomic,
            totalMinor: s.totalMinor,
          ),
        );
      } on QuotationRecoveryLineException catch (error) {
        complete = false;
        lines.add(
          QuotationLineEstimate(quotationItemId: item.id, issue: error.reason),
        );
      }
    }
    return QuotationEstimate(
      calculatedAt: DateTime.now().toUtc(),
      totalMinor: complete && sum <= BigInt.from(SaleItemSnapshot.maxInteger)
          ? sum.toInt()
          : null,
      lines: lines,
    );
  });

  List<Quotation> _map(
    List<({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})>
    rows,
  ) {
    final grouped =
        <
          String,
          List<
            ({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})
          >
        >{};
    for (final row in rows) {
      grouped.putIfAbsent(row.quotation.id, () => []).add(row);
    }
    return [for (final group in grouped.values) _document(group)];
  }

  Quotation _document(
    List<({QuotationRow quotation, QuotationItemRow? item, SaleRow? sale})>
    rows,
  ) {
    final q = rows.first.quotation;
    final sale = rows.first.sale;
    final status = sale?.status == SaleStatus.confirmada.name
        ? QuotationStatus.vendida
        : sale?.active == true && sale?.status == SaleStatus.borrador.name
        ? QuotationStatus.enVenta
        : QuotationStatus.disponible;
    return Quotation(
      id: q.id,
      userId: q.userId,
      deviceId: q.deviceId,
      issuedAtLocal: q.issuedAtLocal.toUtc(),
      sourceSaleId: q.sourceSaleId,
      sourceDraftEventId: q.sourceDraftEventId,
      currentSaleId: q.currentSaleId,
      lastEventId: q.lastEventId,
      status: status,
      items: [
        for (final row in rows)
          if (row.item case final item?)
            QuotationItem(
              id: item.id,
              sortOrder: item.sortOrder,
              variantId: item.variantId,
              productName: item.productNameSnapshot,
              variantName: item.variantNameSnapshot,
              saleMode: item.saleModeSnapshot,
              quantity: item.quantity,
              measuredQuantityAtomic: item.measuredQuantityAtomic,
              unitCode: item.saleUnitCodeSnapshot,
              unitSymbol: item.saleUnitSymbolSnapshot,
              unitAtomicFactor: item.saleUnitAtomicFactorSnapshot,
            ),
      ],
    );
  }
}
