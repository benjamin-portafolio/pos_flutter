import '../../../../domain/ventas/sale_draft.dart';
import '../../../../domain/ventas/sale_draft_item.dart';

/// Formatos compartidos por caja y los indicadores de búsqueda.
class SaleDraftDisplay {
  static String money(int minor) =>
      '\$${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  static String quantity(SaleDraftItem item) => item.quantity != null
      ? '${item.quantity}'
      : '${_measure(BigInt.from(item.measuredQuantityAtomic!), item.unitAtomicFactor!)} ${item.unitSymbol}';

  static String price(SaleDraftItem item) => item.quantity != null
      ? money(item.unitPriceMinor)
      : '${money(item.unitPriceMinor)} / ${_measure(BigInt.from(item.priceReferenceQuantityAtomic!), item.unitAtomicFactor!)} ${item.unitSymbol}';

  static String badge(SaleDraft draft, String variantId) => _quantities(
    draft.items.where((item) => item.variantId == variantId),
    badge: true,
  ).join('\n');

  static String summary(SaleDraft? draft) {
    final count = draft?.articleCount ?? 0;
    return [
      '$count ${count == 1 ? 'artículo' : 'artículos'}',
      ..._quantities(draft?.items ?? []),
    ].join(' · ');
  }

  static String receiptQuantities(Iterable<SaleDraftItem> items) =>
      _quantities(items, abbreviatePieces: true).join(' · ');

  static List<String> _quantities(
    Iterable<SaleDraftItem> items, {
    bool badge = false,
    bool abbreviatePieces = false,
  }) {
    var pieces = BigInt.zero;
    final measures = <(String, String, int), BigInt>{};
    for (final item in items) {
      if (item.quantity != null) {
        pieces += BigInt.from(item.quantity!);
      } else {
        final key = (item.unitCode!, item.unitSymbol!, item.unitAtomicFactor!);
        measures.update(
          key,
          (value) => value + BigInt.from(item.measuredQuantityAtomic!),
          ifAbsent: () => BigInt.from(item.measuredQuantityAtomic!),
        );
      }
    }
    return [
      if (pieces > BigInt.zero)
        badge
            ? '×$pieces'
            : abbreviatePieces
            ? '$pieces pzas'
            : '$pieces ${pieces == BigInt.one ? 'unidad' : 'unidades'}',
      for (final entry in measures.entries)
        '${_measure(entry.value, entry.key.$3)} ${entry.key.$2}',
    ];
  }

  static String _measure(BigInt atomic, int unitFactor) {
    final factor = BigInt.from(unitFactor);
    final whole = atomic ~/ factor;
    var remainder = atomic.remainder(factor);
    if (remainder == BigInt.zero) return '$whole';
    // Mantiene los decimales de unidades decimales (por ejemplo 0.750 kg).
    final decimalFactor = RegExp(r'^10*$').hasMatch('$unitFactor');
    if (decimalFactor) {
      return '$whole.${remainder.toString().padLeft('$unitFactor'.length - 1, '0')}';
    }
    var fraction = '';
    while (remainder != BigInt.zero && fraction.length < 12) {
      remainder *= BigInt.from(10);
      fraction += '${remainder ~/ factor}';
      remainder = remainder.remainder(factor);
    }
    return '${remainder == BigInt.zero ? '' : '≈'}$whole.$fraction';
  }
}
