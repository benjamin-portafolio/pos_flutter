import '../../domain/ventas/sale_status.dart';
import 'payloads/sale_item_snapshot.dart';
import 'projections/sale_item_projection.dart';
import 'projections/sale_projection.dart';

/// Reglas comunes al comando y al handler, ejecutadas bajo su transacción.
class QuotationDraftValidator {
  static List<SaleItemProjection> validate({
    required SaleProjection? sale,
    required String userId,
    required String deviceId,
    required String expectedDraftEventId,
    required List<SaleItemProjection> items,
  }) {
    if (sale == null ||
        !sale.active ||
        sale.status != SaleStatus.borrador ||
        sale.userId != userId ||
        sale.deviceId != deviceId ||
        sale.lastEventId != expectedDraftEventId ||
        sale.version < 1) {
      throw StateError(
        'El borrador cambió o no pertenece al usuario/dispositivo actual.',
      );
    }
    final active = items.where((item) => item.active).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final sum = active.fold(
      BigInt.zero,
      (sum, item) => sum + BigInt.from(item.snapshot.totalMinor),
    );
    if (active.isEmpty ||
        sale.totalMinor < 0 ||
        sale.totalMinor > SaleItemSnapshot.maxInteger ||
        sum != BigInt.from(sale.totalMinor) ||
        active.map((item) => item.id).toSet().length != active.length ||
        active.map((item) => item.sortOrder).toSet().length != active.length ||
        active.any(
          (item) =>
              item.saleId != sale.id ||
              item.id.trim().isEmpty ||
              item.sortOrder < 0 ||
              item.sortOrder > SaleItemSnapshot.maxInteger ||
              (item.persistedTotalMinor != null &&
                  item.persistedTotalMinor != item.snapshot.totalMinor),
        )) {
      throw StateError(
        'El borrador no tiene líneas o sus importes son inválidos.',
      );
    }
    return active;
  }
}
