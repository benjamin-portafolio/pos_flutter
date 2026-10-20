import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../application/sync/payloads/sale_item_snapshot.dart';
import '../../../../application/weighing/scale_exception.dart';
import '../../../../application/weighing/scale_profile.dart';
import '../../../../application/weighing/scale_session.dart';
import '../../../../application/weighing/scale_session_service.dart';
import '../../../../application/weighing/scale_session_snapshot.dart';
import '../../../../domain/inventario/dimension_unidad.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/ventas/measured_sale_conditions.dart';
import '../../../../domain/ventas/sale_draft.dart';
import '../../articulos/measured_sale_preview.dart';
import '../../articulos/sale_quantity_form_result.dart';
import '../../basculas/scale_failure_message.dart';

/// Temporary presentation only. The caller owns catalog revalidation/write.
class SaleWeighingController extends ChangeNotifier {
  SaleWeighingController({
    required this.conditions,
    required this.profile,
    required this.service,
    required Stream<SaleDraft?> draft,
  }) {
    _draftSubscription = draft.listen(
      (value) {
        _draft = value;
        _draftReady = true;
        _draftError = false;
        _calculate();
        _changed();
      },
      onError: (Object _) {
        _draftError = true;
        _calculate();
        _changed();
      },
    );
  }

  final MeasuredSaleConditions conditions;
  final ScaleProfile profile;
  final ScaleSessionService service;
  static const codec = InventoryQuantityCodec();
  static const _preview = MeasuredSalePreview();
  late final StreamSubscription<SaleDraft?> _draftSubscription;
  StreamSubscription<ScaleSessionSnapshot>? _subscription;
  ScaleSession? _session;
  SaleDraft? _draft;
  bool _draftReady = false;
  bool _draftError = false;
  bool _disposed = false;
  bool _submitted = false;
  Future<bool>? _stopping;
  bool paused = true;
  int revision = 0;
  int? _presented;
  String? error;
  SaleItemSnapshot? capture;
  SaleItemSnapshot? accumulated;

  bool get canAccept =>
      !paused &&
      !_submitted &&
      capture != null &&
      _draftReady &&
      !_draftError &&
      _session?.hasFreshWeight == true;
  bool get stopping => _stopping != null;

  void _changed() {
    revision++;
    _presented = null;
    if (!_disposed) notifyListeners();
  }

  void start() {
    if (_disposed || _submitted || _stopping != null || _session != null) {
      return;
    }
    paused = false;
    error = null;
    capture = accumulated = null;
    try {
      final session = service.open(profile, owner: ScaleSessionOwner.sale);
      _session = session;
      _subscription = session.updates.listen((_) {
        if (_disposed ||
            paused ||
            _submitted ||
            !identical(session, _session)) {
          return;
        }
        _calculate();
        _changed();
      });
    } on ScaleException catch (e) {
      error = scaleFailureMessage(e.failure);
      paused = true;
    }
    _changed();
  }

  void _calculate() {
    capture = accumulated = null;
    if (paused || _submitted) return;
    final snapshot = _session?.snapshot;
    error = snapshot?.failure == null
        ? null
        : scaleFailureMessage(snapshot!.failure!);
    if (_draftError) {
      error = 'No se pudo revisar la acumulación. Reintenta la captura.';
      return;
    }
    if (snapshot?.hasUsableWeight != true || _session?.hasFreshWeight != true) {
      return;
    }
    try {
      final unit = conditions.unit;
      if (!unit.activa ||
          unit.dimension != DimensionUnidad.mass ||
          !['kg', 'g'].contains(unit.code) ||
          unit.factorAtomico != (unit.code == 'kg' ? 1000 : 1)) {
        throw const FormatException(
          'La unidad del producto no es compatible con pesaje.',
        );
      }
      // The driver already rejects non-integral grams. Check the exact wire
      // quantity again at this boundary; never trust a rounded grams field.
      final weight = snapshot!.measurement!.weight!;
      final divisor = BigInt.from(10).pow(weight.decimalPlaces);
      final grams = weight.coefficient * BigInt.from(1000);
      if (grams.remainder(divisor) != BigInt.zero) {
        throw const FormatException(
          'El peso contiene una fracción de gramo no representable.',
        );
      }
      final atomicBig = grams ~/ divisor;
      if (atomicBig != BigInt.from(weight.grams)) {
        throw const FormatException('Lectura de peso inconsistente.');
      }
      final quantity = codec.formatAtomic(weight.grams, unit);
      final atomic = codec.parsePositiveAtomic(quantity, unit);
      final next = _preview.capture(conditions, atomic);
      final line = _preview.accumulated(next, _draft);
      capture = next;
      accumulated = line;
    } on FormatException catch (e) {
      error = e.message;
    }
  }

  /// Called only after the frame containing this revision has been painted.
  void presented(int value) {
    if (value == revision && canAccept) _presented = value;
  }

  SaleQuantityFormResult? accept(int reviewedRevision) {
    if (!canAccept || reviewedRevision != revision || _presented != revision) {
      return null;
    }
    final quantity = codec.formatAtomic(
      capture!.measuredQuantityAtomic!,
      conditions.unit,
    );
    _submitted = true;
    final result = SaleQuantityFormResult(
      measuredQuantity: quantity,
      targetAmountMinor: null,
      expectedUnitId: conditions.unit.id,
      expectedUnitPriceMinor: conditions.unitPriceMinor,
      expectedPriceReferenceQuantityAtomic:
          conditions.priceReferenceQuantityAtomic,
      displayQuantity: quantity,
      displayUnitSymbol: conditions.unit.simbolo,
    );
    // Invalidate immediately, before awaiting physical closure or another frame.
    unawaited(stop());
    return result;
  }

  Future<bool> stop() => _stopping ??= _close().whenComplete(() {
    _stopping = null;
    if (!_disposed) notifyListeners();
  });

  Future<bool> _close() async {
    paused = true;
    capture = accumulated = null;
    final closing = _session?.close();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _changed();
    try {
      await closing;
      _session = null;
      return true;
    } on ScaleException catch (e) {
      error = scaleFailureMessage(e.failure);
      _changed();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_draftSubscription.cancel());
    unawaited(stop());
    super.dispose();
  }
}
