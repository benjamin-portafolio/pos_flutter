import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config/app_config.dart';
import 'baseline_bootstrap_transport.dart';
import 'baseline_bootstrap_installer.dart';
import 'recovery_json.dart';

/// S4: bootstrap de cliente vacío sin UI, vínculo del origen ni replay histórico.
class BaselineBootstrapService {
  Future<Map<String, Object?>> installEmpty({
    required AppMode mode,
    required String expectedServer,
    required String expectedGeneration,
    required String expectedDigest,
    required BaselineBootstrapTransport transport,
    required BaselineBootstrapInstaller installer,
  }) async {
    if (mode != AppMode.serverSync) {
      throw StateError('Bootstrap remoto solo admite server_sync.');
    }
    final bytes = await transport.descriptor();
    if (bytes.length > 16777216 ||
        sha256.convert(bytes).toString() != expectedDigest) {
      throw const FormatException('Digest del bootstrap incompatible.');
    }
    final text = utf8.decode(bytes);
    final descriptor = Map<String, Object?>.from(jsonDecode(text) as Map);
    if (recoveryCanonical(descriptor) != text ||
        descriptor['format'] != 'pos-baseline-bootstrap/1' ||
        descriptor['bootstrap_version'] != 1 ||
        descriptor['server_instance_id'] != expectedServer ||
        descriptor['generation_id'] != expectedGeneration) {
      throw const FormatException(
        'Identidad o contrato bootstrap incompatible.',
      );
    }
    final path = await installer.install(descriptor, transport.chunk);
    // El ack ocurre después del commit local. Repetir el mismo ack retorna el
    // mismo dispositivo/token; no se copian permisos del user_id histórico.
    final binding = await transport.bind(
      descriptor['dataset_id'] as String,
      expectedDigest,
    );
    if (binding['server_instance_id'] != expectedServer ||
        binding['generation_id'] != expectedGeneration ||
        binding['dataset_id'] != descriptor['dataset_id'] ||
        binding['baseline_high_watermark'] !=
            descriptor['baseline_high_watermark']) {
      throw const FormatException('Binding de otra generación.');
    }
    return {'database_path': path, 'binding': binding};
  }
}
