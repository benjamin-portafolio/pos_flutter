import 'dart:io';

import '../../../application/config/app_config.dart';
import '../../../application/recovery/baseline_bootstrap_service.dart';
import '../../../application/recovery/empty_device_enrollment.dart';
import '../../../application/sync/sync_network_gate.dart';
import '../../../application/sync/sync_installation.dart';
import 'drift_recovery_source_binder.dart';
import 'http_baseline_bootstrap_transport.dart';
import 'http_connection_attempts.dart';
import 'http_recovery_destination_inspector.dart';
import 'sqlite_baseline_bootstrap_installer.dart';
import 'sync_installation_file_store.dart';

class DriftEmptyDeviceEnrollment implements EmptyDeviceEnrollment {
  DriftEmptyDeviceEnrollment({
    required this.connections,
    required this.binder,
    required this.network,
    this.runtimeInstallation,
  });

  final HttpConnectionAttempts connections;
  final DriftRecoverySourceBinder binder;
  final SyncNetworkGate network;
  final SyncInstallation? runtimeInstallation;
  bool _busy = false;

  @override
  Future<bool> checkAndInstall(
    String endpoint, {
    required AppMode mode,
    AppConfig? setupConfig,
    required void Function() onDownloading,
  }) async {
    if (mode != AppMode.serverSync) {
      throw StateError('El alta de servidor requiere modo servidor.');
    }
    if (_busy) throw StateError('Ya hay una comprobación en curso.');
    _busy = true;
    try {
      var uri = Uri.parse(endpoint);
      final installationStore = SyncInstallationFileStore(binder.directory);
      final installation = await installationStore.read();
      final changingEndpoint =
          installation != null &&
          Uri.parse(installation['endpoint'] as String).replace(path: '') !=
              uri.replace(path: '');
      if (changingEndpoint) {
        uri = HttpRecoveryDestinationInspector.parseDestination(endpoint);
      }
      final health = await connections.health(uri);
      if (installation != null) {
        final binding = installation['binding'] as Map;
        if (health['sync_protocol'] != 2 ||
            binding['server_instance_id'] != health['server_instance_id'] ||
            binding['generation_id'] != health['generation_id']) {
          throw StateError(
            'El destino tiene otra identidad o generación. Usa Recuperar servidor '
            'para preparar una recuperación explícita; se conserva la vinculación actual.',
          );
        }
        if (health['status'] != 'ok' || health['server_mode'] != 'active') {
          throw StateError(
            'El servidor no está disponible para operar. Si hay una recuperación '
            'en curso, cambia su dirección en Recuperar servidor.',
          );
        }
        if (!changingEndpoint) {
          return false;
        }
        final drained = network.pause();
        var committed = false;
        try {
          await drained.timeout(const Duration(seconds: 20));
          await connections.verifyBinding(uri, installation, health);
          final runtime =
              runtimeInstallation ??
              SyncInstallation(installation, persist: installationStore.write);
          await runtime.relocate('$uri');
          committed = true;
          // Both callers restart the runtime on true. Its endpoint, HTTP guards,
          // sockets and credentials are rebuilt from the authoritative file.
          return true;
        } finally {
          if (!committed) network.resume();
        }
      }
      if (health['status'] != 'ok' || health['server_mode'] == 'recovering') {
        throw const FormatException(
          'El servidor no está disponible para operar.',
        );
      }
      final requiresBootstrap =
          health['baseline_bootstrap_required'] == true ||
          (health['baseline_bootstrap_required'] == null &&
              health['server_mode'] == 'active' &&
              (health['capabilities'] as List?)?.contains(
                    'baseline_bootstrap_required',
                  ) ==
                  true);
      if (!requiresBootstrap) return false;

      final safeUri = HttpRecoveryDestinationInspector.parseDestination('$uri');
      final server = health['server_instance_id'];
      final generation = health['generation_id'];
      if (health['sync_protocol'] != 2 ||
          server is! String ||
          generation is! String) {
        throw const FormatException(
          'Destino incompatible con el alta de dispositivos.',
        );
      }

      final drained = network.pause();
      var committed = false;
      try {
        await drained.timeout(const Duration(seconds: 20));
        await binder.assertEmpty();
        final grant = await connections.bootstrap(safeUri, server, generation);
        if (grant['status'] == 'disabled') {
          throw StateError(
            'El alta de dispositivos está deshabilitada en el servidor.',
          );
        }
        final token = grant['token'];
        final digest = grant['bootstrap_digest'];
        if (grant['status'] != 'approved' ||
            token is! String ||
            digest is! String) {
          throw const FormatException('El servidor no autorizó el alta.');
        }
        final transport = HttpBaselineBootstrapTransport(
          baseUri: safeUri,
          serverInstanceId: server,
          generationId: generation,
          enrollmentToken: token,
        );
        onDownloading();
        try {
          final staged = await BaselineBootstrapService().installEmpty(
            mode: mode,
            expectedServer: server,
            expectedGeneration: generation,
            expectedDigest: digest,
            transport: transport,
            installer: SqliteBaselineBootstrapInstaller(
              Directory('${binder.directory.path}/empty-bootstrap'),
            ),
          );
          await binder.installEmpty(
            endpoint: endpoint,
            staged: staged,
            setupConfig: setupConfig,
          );
          committed = true;
          return true;
        } finally {
          transport.close();
        }
      } finally {
        // The new runtime owns a new gate. Keep old network work paused after replacing SQLite.
        if (!committed) network.resume();
      }
    } finally {
      _busy = false;
    }
  }
}
