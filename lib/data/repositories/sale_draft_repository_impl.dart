import '../../domain/repositories/sale_draft_repository.dart';
import '../../domain/ventas/sale_draft.dart';
import '../../domain/ventas/sale_draft_item.dart';
import '../local/drift/app_database.dart';

class SaleDraftRepositoryImpl implements SaleDraftRepository {
  SaleDraftRepositoryImpl({
    required this.saleDao,
    required this.userId,
    required this.deviceId,
  });

  final SaleDao saleDao;
  final String userId;
  final String deviceId;

  @override
  Stream<SaleDraft?> watchCurrentDraft() =>
      saleDao.watchDraft(userId, deviceId).map((rows) {
        if (rows.isEmpty) return null;
        final sale = rows.first.sale;
        return SaleDraft(
          id: sale.id,
          totalMinor: sale.totalMinor,
          items: [
            for (final row in rows)
              if (row.item case final item?)
                SaleDraftItem(
                  id: item.id,
                  variantId: item.variantId,
                  productName: item.productNameSnapshot,
                  variantName: item.variantNameSnapshot,
                  quantity: item.quantity,
                  measuredQuantityAtomic: item.measuredQuantityAtomic,
                  unitPriceMinor: item.unitPriceMinor,
                  priceReferenceQuantityAtomic:
                      item.priceReferenceQuantityAtomicSnapshot,
                  unitCode: item.saleUnitCodeSnapshot,
                  unitSymbol: item.saleUnitSymbolSnapshot,
                  unitAtomicFactor: item.saleUnitAtomicFactorSnapshot,
                  totalMinor: item.totalMinor,
                ),
          ],
        );
      });
}
