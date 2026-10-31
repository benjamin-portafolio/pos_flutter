import 'dart:async';

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
  final _selection = StreamController<String>.broadcast(sync: true);
  String? _selectedDraftId;

  @override
  String? get selectedDraftId => _selectedDraftId;

  @override
  void selectDraft(String saleId) {
    final id = saleId.trim();
    if (id.isEmpty) throw ArgumentError.value(saleId, 'saleId');
    if (_selectedDraftId == id) return;
    _selectedDraftId = id;
    _selection.add(id);
  }

  @override
  Stream<SaleDraft?> watchCurrentDraft() => Stream.multi((controller) {
    List<SaleDraft>? latest;
    void emit() {
      final drafts = latest;
      if (drafts == null) return;
      final selected = _selectedDraftId;
      controller.add(
        selected == null
            ? drafts.firstOrNull
            : drafts.where((draft) => draft.id == selected).firstOrNull,
      );
    }

    final selection = _selection.stream.listen((_) => emit());
    final drafts = watchDrafts().listen((value) {
      latest = value;
      emit();
    }, onError: controller.addError);
    controller.onCancel = () async {
      await selection.cancel();
      await drafts.cancel();
    };
  });

  @override
  Stream<List<SaleDraft>> watchDrafts() =>
      saleDao.watchDraft(userId, deviceId).map((rows) {
        final grouped = <String, List<({SaleRow sale, SaleItemRow? item})>>{};
        for (final row in rows) {
          (grouped[row.sale.id] ??= []).add(row);
        }
        return [for (final group in grouped.values) _mapDraft(group)];
      });

  SaleDraft _mapDraft(List<({SaleRow sale, SaleItemRow? item})> rows) {
    final sale = rows.first.sale;
    return SaleDraft(
      id: sale.id,
      lastEventId: sale.lastEventId,
      version: sale.version,
      pricingMode: sale.pricingMode ?? 'normal',
      totalMinor: sale.totalMinor,
      items: [
        for (final row in rows)
          if (row.item case final item?)
            SaleDraftItem(
              id: item.id,
              variantId: item.variantId,
              priceSnapshotVersion: item.priceSnapshotVersion,
              normalPriceMinorSnapshot: item.normalPriceMinorSnapshot,
              offerPriceMinorSnapshot: item.offerPriceMinorSnapshot,
              effectivePriceSource: item.effectivePriceSource,
              priceSelection: item.priceSelection,
              priceConfigurationEventId: item.priceConfigurationEventId,
              consumptionConfigurationKey: item.consumptionConfigurationKey,
              productName: item.productNameSnapshot,
              variantName: item.variantNameSnapshot,
              quantity: item.quantity,
              measuredQuantityAtomic: item.measuredQuantityAtomic,
              unitPriceMinor: item.unitPriceMinor,
              standardCostMinor: item.standardCostMinorSnapshot,
              priceReferenceQuantityAtomic:
                  item.priceReferenceQuantityAtomicSnapshot,
              unitCode: item.saleUnitCodeSnapshot,
              unitSymbol: item.saleUnitSymbolSnapshot,
              unitAtomicFactor: item.saleUnitAtomicFactorSnapshot,
              totalMinor: item.totalMinor,
            ),
      ],
    );
  }
}
