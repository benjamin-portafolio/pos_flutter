import 'sale_item_snapshot.dart';
import '../local_event_store.dart';
import 'sale_adjustment_payload.dart';
import 'venta_confirmada_payload.dart';

/// Reglas v1; ejecutar dentro de la transacción después de buscar reintentos.
class SaleAdjustmentRules {
  static const maxInteger = 9007199254740991;
  static int cumulative(int total, int quantity, int original) {
    if (total < 0 ||
        total > maxInteger ||
        original <= 0 ||
        original > maxInteger ||
        quantity < 0 ||
        quantity > original) {
      throw const FormatException('Acumulado fuera de rango.');
    }
    final n = BigInt.from(total) * BigInt.from(quantity);
    final d = BigInt.from(original);
    return ((n * BigInt.two + d) ~/ (d * BigInt.two)).toInt();
  }

  static void validate(
    SaleAdjustmentPayload p,
    VentaConfirmadaPayload original, {
    required String confirmationEventId,
    required String saleId,
    required List<SaleAdjustmentPayload> history,
  }) {
    for (var i = 0; i < history.length; i++) {
      _validateOne(
        history[i],
        original,
        confirmationEventId: confirmationEventId,
        saleId: saleId,
        history: history.sublist(0, i),
      );
    }
    _validateOne(
      p,
      original,
      confirmationEventId: confirmationEventId,
      saleId: saleId,
      history: history,
    );
  }

  static void _validateOne(
    SaleAdjustmentPayload p,
    VentaConfirmadaPayload original, {
    required String confirmationEventId,
    required String saleId,
    required List<SaleAdjustmentPayload> history,
  }) {
    if (p.schemaVersion != 1 ||
        p.saleId != saleId ||
        p.confirmationEventId != confirmationEventId ||
        p.expectedRevision != history.length ||
        p.previousAdjustmentEventId !=
            (history.isEmpty ? null : history.last.eventId) ||
        history.any((h) => h.kind == 'void') ||
        (p.kind == 'void' && history.isNotEmpty) ||
        p.eventId == p.confirmationEventId ||
        p.eventId == p.operationId ||
        history.any(
          (h) => h.eventId == p.eventId || h.operationId == p.operationId,
        )) {
      throw const FormatException('Identidad, estado o revisión obsoleta.');
    }
    final date = DateTime.fromMillisecondsSinceEpoch(
      p.occurredAtMs,
      isUtc: true,
    ).add(Duration(minutes: p.utcOffsetMinutes));
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (date.year > 9999 ||
        day != p.businessDate ||
        p.lines.isEmpty ||
        p.lines.map((l) => l.saleItemId).toSet().length != p.lines.length ||
        (p.kind == 'void' && p.lines.length != original.lines.length)) {
      throw const FormatException('Fecha o líneas inválidas.');
    }
    final deps = p.dependencyEventIds.toSet();
    final requiredDeps = {
      confirmationEventId,
      if (p.previousAdjustmentEventId != null) p.previousAdjustmentEventId!,
      if (p.settlement.cash != null) p.settlement.cash!.openingEventId,
    };
    if (deps.length != p.dependencyEventIds.length ||
        deps.contains(p.eventId) ||
        !deps.containsAll(requiredDeps)) {
      throw const FormatException('Dependencias inválidas.');
    }
    var sum = BigInt.zero;
    final reservedMovements = <String>{
      for (final source in original.lines)
        for (final c in source.consumptions)
          if (c.movementId != null) c.movementId!,
      if (original.cash != null) original.cash!.movementId,
      for (final h in history) ...[
        if (h.settlement.cash != null) h.settlement.cash!.movementId,
        for (final line in h.lines)
          for (final m in line.stock) m.movementId,
      ],
    };
    final movementIds = <String>{};
    for (final l in p.lines) {
      final matches = original.lines.where((x) => x.id == l.saleItemId);
      if (matches.length != 1) throw const FormatException('Línea ajena.');
      final source = matches.single;
      final s = source.snapshot;
      final q = s.quantity ?? s.measuredQuantityAtomic!;
      final previous = history
          .expand((h) => h.lines)
          .where((x) => x.saleItemId == l.saleItemId);
      final returned = previous.fold(
        BigInt.zero,
        (a, x) => a + BigInt.from(x.quantityAtomic),
      );
      final recovered = previous
          .where((x) => x.destination == 'restock')
          .fold(BigInt.zero, (a, x) => a + BigInt.from(x.quantityAtomic));
      if (returned + BigInt.from(l.quantityAtomic) > BigInt.from(q) ||
          (p.kind == 'void' &&
              (l.quantityAtomic != q || l.destination != 'void')) ||
          (p.kind == 'return' &&
              (l.destination == 'void' ||
                  (source.consumptionMode == 'none'
                      ? l.destination != 'untracked'
                      : l.destination == 'untracked') ||
                  (source.consumptionMode == 'recipe' &&
                      l.destination == 'restock'))) ||
          (l.destination == 'not_restockable' && l.reason == null)) {
        throw const FormatException('Cantidad o destino inválido.');
      }
      final before = returned.toInt(), recoveredBefore = recovered.toInt();
      final amount =
          cumulative(s.totalMinor, before + l.quantityAtomic, q) -
          cumulative(s.totalMinor, before, q);
      final restore = p.kind == 'void' || l.destination == 'restock';
      final recoveryAfter = recoveredBefore + (restore ? l.quantityAtomic : 0);
      final historicalCost = historicalCostMinor(s);
      final cost = historicalCost == null
          ? null
          : cumulative(historicalCost, recoveryAfter, q) -
                cumulative(historicalCost, recoveredBefore, q);
      if (l.amountMinor != amount || l.recoveredCostMinor != cost) {
        throw const FormatException('Importe o costo manipulado.');
      }
      final expected = {
        for (final c in source.consumptions)
          if (restore &&
              c.deltaAtomic != 0 &&
              cumulative(-c.deltaAtomic, recoveryAfter, q) -
                      cumulative(-c.deltaAtomic, recoveredBefore, q) >
                  0)
            c.movementId!: c,
      };
      if (l.stock.length != expected.length) {
        throw const FormatException('Restitución incompleta.');
      }
      final seen = <String>{};
      for (final stock in l.stock) {
        final c = expected[stock.originalMovementId];
        if (c == null ||
            !seen.add(stock.originalMovementId) ||
            !movementIds.add(stock.movementId) ||
            reservedMovements.contains(stock.movementId) ||
            stock.movementId == p.eventId ||
            stock.movementId == p.operationId ||
            history.any(
              (h) => h.lines.any(
                (x) => x.stock.any((m) => m.movementId == stock.movementId),
              ),
            ) ||
            stock.inventoryItemId != c.inventoryItemId ||
            stock.quantityAtomic !=
                cumulative(-c.deltaAtomic, recoveryAfter, q) -
                    cumulative(-c.deltaAtomic, recoveredBefore, q)) {
          throw const FormatException('Movimiento manipulado.');
        }
      }
      sum += BigInt.from(amount);
    }
    if (sum != BigInt.from(p.totalMinor)) {
      throw const FormatException('Total incorrecto.');
    }
    final t = p.settlement;
    if (t.method != original.paymentMethod ||
        t.paymentId != original.paymentId ||
        t.clienteId != original.clienteId ||
        (t.method == 'credit'
            ? t.action != 'credit_reduction'
            : p.totalMinor == 0
            ? t.action != 'no_money'
            : !(t.action == 'refund_completed' ||
                  (p.kind == 'void' && t.action == 'unreceived_correction'))) ||
        (t.method == 'transfer' &&
            p.totalMinor > 0 &&
            t.action == 'refund_completed' &&
            t.reference == null) ||
        ((t.cashEnabled && t.method == 'cash' && p.totalMinor > 0) !=
            (t.cash != null)) ||
        (t.cash != null &&
            (!movementIds.add(t.cash!.movementId) ||
                reservedMovements.contains(t.cash!.movementId) ||
                t.cash!.movementId == p.eventId ||
                t.cash!.movementId == p.operationId))) {
      throw const FormatException('Liquidación inválida.');
    }
  }

  /// Paid bookkeeping differs from the physical cash declaration.
  static Map<String, int> paidMoneyEffects(SaleAdjustmentPayload p) => {
    'accounting_delta_minor': p.settlement.method == 'credit'
        ? 0
        : -p.totalMinor,
    'physical_cash_delta_minor':
        p.settlement.method == 'cash' &&
            p.settlement.action == 'refund_completed'
        ? -p.totalMinor
        : 0,
  };

  static void validateCash(
    SaleAdjustmentPayload p, {
    required bool enabled,
    required bool open,
    required String? sessionId,
    required String? openingEventId,
  }) {
    final t = p.settlement;
    if (t.cashEnabled != enabled ||
        (t.cash != null &&
            (!open ||
                t.cash!.sessionId != sessionId ||
                t.cash!.openingEventId != openingEventId))) {
      throw const FormatException('Se requiere la caja actual abierta.');
    }
  }

  /// Costo histórico común al preview y a la validación transaccional.
  static int? historicalCostMinor(SaleItemSnapshot snapshot) =>
      snapshot.standardCostMinor == null
      ? null
      : _cost(
          snapshot.standardCostMinor!,
          snapshot.quantity ?? snapshot.measuredQuantityAtomic!,
          snapshot.priceReferenceQuantityAtomic ?? 1,
        );

  static int _cost(int cost, int q, int reference) {
    final n = BigInt.from(cost) * BigInt.from(q), d = BigInt.from(reference);
    final value = (n * BigInt.two + d) ~/ (d * BigInt.two);
    if (value > BigInt.from(maxInteger)) {
      throw const FormatException('Costo fuera de rango.');
    }
    return value.toInt();
  }

  /// Complete impact set derived from the frozen original, never the live catalog.
  static List<LocalEventRef> refs(
    SaleAdjustmentPayload p,
    VentaConfirmadaPayload original,
  ) {
    final refs = <LocalEventRef>[
      LocalEventRef.affects(refType: 'sale', refId: p.saleId),
      LocalEventRef.affects(refType: 'sale_adjustment', refId: p.operationId),
      for (final id in p.dependencyEventIds)
        LocalEventRef.uses(refType: 'event', refId: id),
      if (p.settlement.paymentId != null)
        LocalEventRef.uses(refType: 'payment', refId: p.settlement.paymentId!),
      if (p.settlement.clienteId != null)
        LocalEventRef.uses(refType: 'cliente', refId: p.settlement.clienteId!),
      if (p.settlement.method == 'credit') ...[
        LocalEventRef.affects(refType: 'credit', refId: p.saleId),
        LocalEventRef.affects(
          refType: 'customer_account',
          refId: p.settlement.clienteId!,
        ),
      ],
      ...?p.settlement.cash?.refs,
      for (final l in p.lines) ...[
        LocalEventRef.affects(refType: 'sale_item', refId: l.saleItemId),
        for (final source in original.lines.where(
          (x) => x.id == l.saleItemId,
        )) ...[
          LocalEventRef.uses(refType: 'product', refId: source.productId),
          LocalEventRef.uses(
            refType: 'product_variant',
            refId: source.snapshot.variantId,
          ),
          if (source.consumptionMode == 'recipe')
            LocalEventRef.uses(
              refType: 'recipe',
              refId: source.snapshot.variantId,
            ),
          if (source.saleUnitId != null)
            LocalEventRef.uses(refType: 'unit', refId: source.saleUnitId!),
          for (final c in source.consumptions)
            LocalEventRef.uses(
              refType: 'inventory_item',
              refId: c.inventoryItemId,
            ),
        ],
        for (final stock in l.stock) ...[
          LocalEventRef.affects(
            refType: 'inventory_item',
            refId: stock.inventoryItemId,
          ),
          LocalEventRef.uses(
            refType: 'inventory_movement',
            refId: stock.originalMovementId,
          ),
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: stock.movementId,
          ),
        ],
      ],
    ];
    final unique = {
      for (final r in refs) '${r.refType}/${r.refId}/${r.relationship}': r,
    };
    if (unique.isEmpty ||
        unique.values.any(
          (r) =>
              r.refId.trim().isEmpty ||
              !['affects', 'uses'].contains(r.relationship),
        )) {
      throw const FormatException('Referencias inválidas.');
    }
    return List.unmodifiable(unique.values);
  }
}
