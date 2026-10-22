import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../application/weighing/scale_profile.dart';
import '../../../../application/weighing/scale_session_service.dart';
import '../../../../domain/ventas/measured_sale_conditions.dart';
import '../../../../domain/ventas/sale_draft.dart';
import '../../articulos/sale_quantity_dialog.dart';
import '../../articulos/sale_quantity_form_result.dart';
import '../models/sale_draft_display.dart';
import 'sale_weighing_controller.dart';

/// Weight capture for eligible measured sales; returns an intention.
class SaleWeighingDialog extends StatefulWidget {
  const SaleWeighingDialog({
    super.key,
    required this.conditions,
    required this.watchDraft,
    required this.profile,
    required this.service,
    required this.loadManualConditions,
    this.initiallyPaused = false,
  });

  final MeasuredSaleConditions conditions;

  /// Each dialog obtains its own observable query, including its initial value.
  final Stream<SaleDraft?> Function() watchDraft;
  final ScaleProfile profile;
  final ScaleSessionService service;
  final Future<MeasuredSaleConditions?> Function() loadManualConditions;
  final bool initiallyPaused;

  @override
  State<SaleWeighingDialog> createState() => _SaleWeighingDialogState();
}

class _SaleWeighingDialogState extends State<SaleWeighingDialog>
    with WidgetsBindingObserver {
  late final _controller = SaleWeighingController(
    conditions: widget.conditions,
    profile: widget.profile,
    service: widget.service,
    draft: widget.watchDraft(),
  );
  ModalRoute<dynamic>? _route;
  bool _windowFocused = true;
  bool _enterArmed = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _manual = false;
  late int _activityRevision = widget.initiallyPaused ? 1 : 0;
  SaleQuantityFormResult? _accepted;

  bool get _active =>
      _windowFocused &&
      _route?.isCurrent != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active && _activityRevision == 0) {
        _enterArmed = !_enterHeld;
        _controller.start();
      }
    });
  }

  bool get _enterHeld => HardwareKeyboard.instance.logicalKeysPressed.any(
    (key) =>
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter,
  );

  void _changed() {
    if (mounted) setState(() {});
  }

  void _pause() {
    _activityRevision++;
    _enterArmed = false;
    unawaited(_controller.stop());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.secondaryAnimation?.removeListener(_routeChanged);
      _route = route;
      _route?.secondaryAnimation?.addListener(_routeChanged);
    }
    if (route?.isCurrent == false) {
      // Invalidate synchronously; notifier can run during dependency updates.
      _controller.removeListener(_changed);
      _pause();
      _controller.addListener(_changed);
    }
  }

  void _routeChanged() {
    if (_route?.isCurrent == false) _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _windowFocused = event.state == ViewFocusState.focused;
    if (!_windowFocused) _pause();
  }

  Future<void> _resume() async {
    if (!_active || _leaving || _manual) return;
    final activityRevision = _activityRevision;
    _enterArmed = !_enterHeld;
    if (await _controller.stop() &&
        mounted &&
        _active &&
        !_leaving &&
        !_manual &&
        activityRevision == _activityRevision) {
      _controller.start();
    }
  }

  Future<void> _finish({bool manual = false}) async {
    if (_leaving || _manual) return;
    setState(() => _leaving = true);
    final closed = await _controller.stop();
    if (!mounted) return;
    if (!closed) {
      setState(() => _leaving = false);
      return;
    }
    if (manual && _accepted == null) {
      _manual = true;
      final result = await showDialog<SaleQuantityFormResult>(
        context: context,
        builder: (_) => SaleQuantityDialog(
          loadConditions: widget.loadManualConditions,
          draft: widget.watchDraft(),
        ),
      );
      if (!mounted) return;
      _accepted = result;
      _manual = false;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_accepted);
    });
  }

  void _accept(int revision) {
    if (!_active || _leaving || _manual) return;
    final result = _controller.accept(revision);
    if (result == null) return;
    _accepted = result;
    unawaited(_finish());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _route?.secondaryAnimation?.removeListener(_routeChanged);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final conditions = widget.conditions;
    final unit = conditions.unit;
    final revision = c.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active) c.presented(revision);
    });
    final capture = c.capture;
    final line = c.accumulated;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish());
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) {
            // A HID barcode burst must not confirm the current product with
            // its trailing Enter. A following standalone press is deliberate.
            if (event is KeyDownEvent &&
                (event.character != null ||
                    RegExp(r'^[0-9]$').hasMatch(event.logicalKey.keyLabel))) {
              _enterArmed = false;
            }
            return KeyEventResult.ignored;
          }
          if (event is KeyUpEvent) {
            _enterArmed = true;
          } else if (event is KeyDownEvent && _enterArmed) {
            _enterArmed = false;
            _accept(revision);
          }
          return KeyEventResult.handled;
        },
        child: AlertDialog(
          scrollable: true,
          title: Text(
            [
              conditions.productName,
              if (conditions.variantName != null) conditions.variantName!,
            ].join(' · '),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Precio: ${SaleDraftDisplay.money(conditions.unitPriceMinor)} / '
                  '${SaleWeighingController.codec.formatAtomic(conditions.priceReferenceQuantityAtomic, unit)} ${unit.simbolo}',
                ),
                Text('Báscula: ${widget.profile.alias}'),
                const SizedBox(height: 16),
                if (capture != null) ...[
                  Text(
                    'Peso: ${SaleWeighingController.codec.formatAtomic(capture.measuredQuantityAtomic!, unit)} ${unit.simbolo}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Importe: ${SaleDraftDisplay.money(capture.totalMinor)}',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  const Text(
                    'Estabilidad no informada. Confirma el peso manualmente.',
                  ),
                  if (line != null)
                    Text(
                      'Línea acumulada prevista: '
                      '${SaleWeighingController.codec.formatAtomic(line.measuredQuantityAtomic!, unit)} '
                      '${unit.simbolo} · ${SaleDraftDisplay.money(line.totalMinor)}',
                    ),
                ] else
                  Text(
                    c.paused
                        ? 'Pesaje detenido. Reanuda para recibir una lectura nueva.'
                        : 'Esperando lectura nueva…',
                  ),
                if (c.error != null)
                  Semantics(liveRegion: true, child: Text(c.error!)),
              ],
            ),
          ),
          actions: [
            if (_accepted == null)
              TextButton(
                onPressed: _leaving ? null : () => _finish(),
                child: const Text('Cancelar'),
              ),
            if (_accepted == null)
              TextButton(
                onPressed: _leaving ? null : () => _finish(manual: true),
                child: const Text('Captura manual'),
              ),
            if (c.paused || c.error != null)
              OutlinedButton(
                onPressed: _leaving || c.stopping
                    ? null
                    : _accepted != null
                    ? () => _finish()
                    : _resume,
                child: Text(
                  _accepted != null
                      ? 'Reintentar cierre'
                      : c.paused
                      ? 'Reanudar'
                      : 'Reintentar',
                ),
              ),
            FilledButton(
              onPressed: c.canAccept && !_leaving
                  ? () => _accept(revision)
                  : null,
              child: Text(_leaving ? 'Cerrando báscula…' : 'Aceptar'),
            ),
          ],
        ),
      ),
    );
  }
}
