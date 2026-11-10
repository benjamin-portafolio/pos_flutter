import 'dart:io';
import '../config/app_config.dart';
import 'recovery_cancellation.dart';
import 'recovery_snapshot.dart';

/// Puerto de captura; no recibe endpoints, credenciales ni servicios de sync.
abstract interface class RecoverySnapshotSource {
  Future<RecoverySnapshot> capture({
    required Directory privateDirectory,
    required AppMode mode,
    required String deviceId,
    required String appRevision,
    required RecoveryCancellation cancellation,
  });
  Future<bool> hasChangesSince(RecoverySnapshot snapshot);
}
