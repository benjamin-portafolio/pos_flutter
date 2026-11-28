import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/sync_availability_snapshot.dart';
import 'models/sync_local_status.dart';
import 'sync_activity.dart';
import 'sync_availability_monitor.dart';
import 'sync_status_store.dart';

/// Estado compartido por el encabezado, el menú y el detalle. No inicia red.
class SyncStatusController extends ChangeNotifier {
  SyncStatusController({
    required SyncStatusStore store,
    required SyncActivity activity,
    required SyncAvailabilityMonitor monitor,
    this.validFor = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _activity = activity,
       _monitor = monitor,
       _now = now ?? DateTime.now {
    _subscription = store.watch().listen(
      (value) {
        local = value;
        localError = null;
        if (value.pending > 0 && !_activity.isRunning) _activity.invalidate();
        notifyListeners();
      },
      onError: (Object error) {
        local = null;
        localError = 'No se pudo consultar el estado local: $error';
        notifyListeners();
      },
    );
    _availabilitySubscription = monitor.snapshots.listen((_) {
      if (!monitor.snapshot.isAvailable &&
          monitor.snapshot.status != SyncAvailabilityStatus.checking) {
        _activity.invalidate();
      }
      notifyListeners();
    });
    _activity.addListener(notifyListeners);
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => notifyListeners(),
    );
  }

  final SyncActivity _activity;
  final SyncAvailabilityMonitor _monitor;
  final DateTime Function() _now;
  final Duration validFor;
  late final StreamSubscription<SyncLocalStatus> _subscription;
  late final StreamSubscription<SyncAvailabilitySnapshot>
  _availabilitySubscription;
  late final Timer _timer;
  SyncLocalStatus? local;
  String? localError;

  SyncAvailabilitySnapshot get availability => _monitor.snapshot;
  DateTime? get verifiedAt => _activity.verifiedAt;
  String? get error => localError ?? _activity.error;
  bool get busy =>
      _activity.isRunning ||
      availability.status == SyncAvailabilityStatus.checking;
  bool get isCurrent =>
      local != null &&
      local!.pending == 0 &&
      local!.problems.isEmpty &&
      error == null &&
      !busy &&
      availability.isAvailable &&
      _activity.hasVerification &&
      verifiedAt != null &&
      _now().difference(verifiedAt!) < validFor;

  String get label {
    if (localError != null) return 'No se pudo comprobar la sincronización';
    final problems = local?.problems.length ?? 0;
    if (problems == 1) return '1 cambio requiere atención';
    if (problems > 1) return '$problems cambios requieren atención';
    if (availability.status == SyncAvailabilityStatus.misconfigured) {
      return 'Revisar configuración';
    }
    if (availability.status == SyncAvailabilityStatus.unavailable) {
      final pending = local?.pending ?? 0;
      return 'Sin conexión con el servidor${pending > 0 ? ' · $pending por enviar' : ''}';
    }
    if (busy) return 'Sincronizando…';
    final pending = local?.pending ?? 0;
    if (pending == 1) return '1 cambio por enviar';
    if (pending > 1) return '$pending cambios por enviar';
    if (error != null) return 'No se pudo completar la sincronización';
    if (isCurrent) {
      final seconds = _now().difference(verifiedAt!).inSeconds;
      return 'Sincronizado · verificado hace ${seconds < 1 ? 1 : seconds} s';
    }
    return 'Sincronización por comprobar';
  }

  Future<void> checkNow() => _monitor.checkNow();

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_subscription.cancel());
    unawaited(_availabilitySubscription.cancel());
    _activity.removeListener(notifyListeners);
    super.dispose();
  }
}
