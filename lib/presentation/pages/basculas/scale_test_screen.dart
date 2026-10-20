import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';

import '../../../application/weighing/scale_exception.dart';
import '../../../application/weighing/scale_failure.dart';
import '../../../application/weighing/scale_profile.dart';
import '../../../application/weighing/scale_session.dart';
import '../../../application/weighing/scale_session_service.dart';
import '../../../application/weighing/scale_session_snapshot.dart';
import '../../../application/weighing/scale_weight.dart';
import 'scale_failure_message.dart';

/// Read-only diagnostics. The lease always closes before a normal navigation.
class ScaleTestScreen extends StatefulWidget {
  const ScaleTestScreen({
    super.key,
    required this.profile,
    required this.service,
  });

  final ScaleProfile profile;
  final ScaleSessionService service;

  @override
  State<ScaleTestScreen> createState() => _ScaleTestScreenState();
}

class _ScaleTestScreenState extends State<ScaleTestScreen>
    with WidgetsBindingObserver {
  ScaleSession? _session;
  StreamSubscription<ScaleSessionSnapshot>? _subscription;
  ScaleSessionSnapshot? _snapshot;
  ScaleFailure? _failure;
  ModalRoute<dynamic>? _route;
  Future<bool>? _stopping;
  bool _paused = true;
  bool _leaving = false;
  bool _allowPop = false;
  bool _windowFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
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
    // ModalRoute.of also observes isCurrent changes.
    if (route?.isCurrent == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_stop());
      });
    }
  }

  void _routeChanged() {
    if (_route?.isCurrent == false) unawaited(_stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _windowFocused = event.state == ViewFocusState.focused;
    if (!_windowFocused) unawaited(_stop());
  }

  void _start() {
    if (_stopping != null || _session != null || _leaving || !_windowFocused) {
      return;
    }
    final activity = WidgetsBinding.instance.lifecycleState;
    if (activity != null && activity != AppLifecycleState.resumed) return;
    if (_route?.isCurrent == false) return;
    _snapshot = null;
    _failure = null;
    _paused = false;
    try {
      final session = widget.service.open(
        widget.profile,
        owner: ScaleSessionOwner.test,
      );
      _session = session;
      _snapshot = session.snapshot;
      unawaited(_subscription?.cancel());
      _subscription = session.updates.listen((snapshot) {
        if (!mounted || _paused || !identical(_session, session)) return;
        setState(() {
          _snapshot = snapshot;
          _failure = snapshot.failure;
          if (snapshot.state == ScaleSessionState.closed) {
            _session = null;
            _paused = true;
          }
        });
      });
    } on ScaleException catch (error) {
      _failure = error.failure;
      _paused = true;
    }
  }

  Future<bool> _stop() =>
      _stopping ??= _close().whenComplete(() => _stopping = null);

  Future<bool> _close() async {
    if (mounted) {
      setState(() {
        _paused = true;
        _snapshot = null;
      });
    }
    // Invalidate the lease before any asynchronous cleanup can yield.
    final closing = _session?.close();
    unawaited(_subscription?.cancel());
    _subscription = null;
    try {
      await closing;
      _session = null;
      return true;
    } catch (_) {
      if (mounted) setState(() => _failure = ScaleFailure.closeFailed);
      return false;
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final closed = await _stop();
    if (!mounted) return;
    if (closed) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      setState(() => _leaving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _route?.secondaryAnimation?.removeListener(_routeChanged);
    unawaited(_subscription?.cancel());
    // External removal cannot await. The singleton retains a failed-close lease;
    // configuration offers an explicit retry instead of evading that ownership.
    final session = _session;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
    super.dispose();
  }

  String _weight(ScaleWeight weight) {
    final digits = weight.coefficient.abs().toString().padLeft(
      weight.decimalPlaces + 1,
      '0',
    );
    final split = digits.length - weight.decimalPlaces;
    final sign = weight.coefficient.isNegative ? '-' : '';
    return '$sign${digits.substring(0, split)}${weight.decimalPlaces == 0 ? '' : '.${digits.substring(split)}'} ${weight.unit.name}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final weight = snapshot?.measurement?.weight;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Prueba de lectura')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.profile.alias,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Rhino BAR-8RS · ${widget.profile.port} · 9600 / 8N1'),
            const SizedBox(height: 24),
            if (!_paused && snapshot?.state == ScaleSessionState.connecting)
              const Text('Conectando…')
            else if (!_paused && weight != null)
              Text(
                _weight(weight),
                style: Theme.of(context).textTheme.displaySmall,
              )
            else if (_failure == null)
              Text(_paused ? 'Prueba detenida.' : 'Esperando lectura…'),
            if (_failure case final failure?)
              Text(scaleFailureMessage(failure)),
            if (!_paused && snapshot?.hasUsableWeight == true)
              const Text(
                'Lectura recibida. Estabilidad no informada por el protocolo.',
              ),
            const SizedBox(height: 16),
            const Text('La prueba solo muestra lecturas de la báscula.'),
            if (_paused && _session == null && !_leaving)
              OutlinedButton(
                onPressed: () => setState(_start),
                child: const Text('Reanudar prueba'),
              ),
            if (_paused && _session != null && !_leaving)
              OutlinedButton(
                onPressed: () async {
                  if (await _stop() && mounted) setState(() => _failure = null);
                },
                child: const Text('Reintentar cierre'),
              ),
            FilledButton(
              onPressed: _leaving ? null : _leave,
              child: Text(_leaving ? 'Cerrando puerto…' : 'Cerrar prueba'),
            ),
          ],
        ),
      ),
    );
  }
}
