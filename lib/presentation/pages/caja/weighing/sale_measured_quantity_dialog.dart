import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../application/weighing/scale_session_service.dart';
import '../../../../application/weighing/scale_settings_controller.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/inventario/dimension_unidad.dart';
import '../../../../domain/ventas/measured_sale_conditions.dart';
import '../../../../domain/ventas/sale_draft.dart';
import '../../articulos/sale_quantity_dialog.dart';
import 'sale_weighing_dialog.dart';

/// Routes measured sales to the configured scale or manual quantity capture.
class SaleMeasuredQuantityDialog extends StatefulWidget {
  const SaleMeasuredQuantityDialog({
    required this.loadConditions,
    required this.watchDraft,
    required this.allowWeighing,
    super.key,
  });

  final Future<MeasuredSaleConditions?> Function() loadConditions;
  final Stream<SaleDraft?> Function() watchDraft;
  final bool allowWeighing;

  @override
  State<SaleMeasuredQuantityDialog> createState() =>
      _SaleMeasuredQuantityDialogState();
}

class _SaleMeasuredQuantityDialogState extends State<SaleMeasuredQuantityDialog>
    with WidgetsBindingObserver {
  bool _interrupted = false;
  ModalRoute<dynamic>? _route;
  late final _conditions = widget.loadConditions();
  // Snapshot the confirmed configuration for this capture. No reload, discovery
  // or implicit change of destination while a product is being weighed.
  late final _settings = getIt.isRegistered<ScaleSettingsController>()
      ? getIt<ScaleSettingsController>()
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Freeze configuration before the asynchronous catalog query completes.
    _profile;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      _route?.secondaryAnimation?.removeListener(_routeChanged);
      _route = route;
      _route?.secondaryAnimation?.addListener(_routeChanged);
    }
    _routeChanged();
  }

  void _routeChanged() {
    if (_route?.isCurrent == false) _interrupted = true;
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId == View.of(context).viewId &&
        event.state != ViewFocusState.focused) {
      _interrupted = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _interrupted = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _route?.secondaryAnimation?.removeListener(_routeChanged);
    super.dispose();
  }

  late final _profile =
      _settings?.loaded == true && _settings?.loadError == null
      ? _settings!.settings.profiles
            .where((p) => p.id == _settings.settings.defaultId)
            .firstOrNull
      : null;

  @override
  Widget build(BuildContext context) => FutureBuilder<MeasuredSaleConditions?>(
    future: _conditions,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const AlertDialog(content: LinearProgressIndicator());
      }
      final conditions = snapshot.data;
      final unit = conditions?.unit;
      if (widget.allowWeighing &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.windows &&
          conditions != null &&
          unit != null &&
          unit.activa &&
          unit.dimension == DimensionUnidad.mass &&
          (unit.code == 'kg' || unit.code == 'g') &&
          _profile != null &&
          getIt.isRegistered<ScaleSessionService>()) {
        return SaleWeighingDialog(
          initiallyPaused: _interrupted,
          conditions: conditions,
          watchDraft: widget.watchDraft,
          profile: _profile,
          service: getIt<ScaleSessionService>(),
          loadManualConditions: widget.loadConditions,
        );
      }
      // Reuse even the manual dialog's missing/stale conditions error handling.
      return SaleQuantityDialog(
        loadConditions: () => _conditions,
        draft: widget.watchDraft(),
      );
    },
  );
}
