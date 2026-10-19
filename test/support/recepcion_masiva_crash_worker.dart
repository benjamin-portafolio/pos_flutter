// Subproceso de prueba: el padre mata ESTE flutter_tester (pid), sin permitir
// dispose/rollback de Dart, para comprobar recuperación de SQLite tras cierre.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/edicion_masiva/resultado_operacion_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_diario_edicion_masiva.dart';

void main() {
  test('trabajador de cierre abrupto', () async {
    final env = Platform.environment;
    final db = AppDatabase.forTesting(
      NativeDatabase(File(env['POS_RECEIPT_DB']!)),
    );
    final config = AppConfigController(
      AppConfig.initial.copyWith(
        mode: AppMode.fromStorage(env['POS_RECEIPT_MODE']),
      ),
    );
    final journal = _CrashJournal(
      db: db,
      config: config,
      context: const LocalCommandContext(
        deviceId: 'crash-device',
        userId: 'crash-user',
      ),
      pauseBeforeCommit: env['POS_RECEIPT_PHASE'] == 'before',
    );
    await EdicionMasivaCommandService(journal).continuar('crash');
    await pause();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> pause() async {
  final markerPath = Platform.environment['POS_RECEIPT_MARKER']!;
  // Publicar el marcador solo cuando su JSON esté completo. La existencia del
  // archivo creado por writeAsString no garantiza que ya se haya escrito.
  final temporal = File('$markerPath.writing');
  await temporal.writeAsString(jsonEncode({'pid': pid}), flush: true);
  await temporal.rename(markerPath);
  await Completer<void>().future;
}

class _CrashJournal extends DriftDiarioEdicionMasiva {
  _CrashJournal({
    required super.db,
    required super.config,
    required super.context,
    required this.pauseBeforeCommit,
  });
  final bool pauseBeforeCommit;
  @override
  Future<void> completar(ResultadoOperacionMasiva result) async {
    await super.completar(result);
    if (pauseBeforeCommit) await pause();
  }
}
