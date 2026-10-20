import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/weighing/scale_profile.dart';
import '../../../application/weighing/scale_serial_settings.dart';
import '../../../application/weighing/scale_settings.dart';
import '../../../application/weighing/scale_settings_exception.dart';
import '../../../application/weighing/scale_settings_store.dart';

class ScaleSettingsFileStore implements ScaleSettingsStore {
  ScaleSettingsFileStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<void> _pending = Future.value();
  int _sequence = 0;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File> _file() async =>
      File(p.join((await _directoryProvider()).path, 'scale_settings.json'));

  @override
  Future<ScaleSettings> readSettings() => _serialize(() async {
    try {
      return await _read(await _file());
    } on ScaleSettingsException {
      rethrow;
    } catch (_) {
      throw const ScaleSettingsException(ScaleSettingsFailure.readFailed);
    }
  });

  Future<ScaleSettings> _read(File file) async {
    // Only a genuine missing path is empty. exists/stat can hide permission
    // errors as "not found"; read directly so those remain I/O failures.
    final List<int> contents;
    try {
      contents = await file.readAsBytes();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return ScaleSettings(profiles: const []);
      }
      rethrow;
    }
    try {
      final json = jsonDecode(utf8.decode(contents)) as Map<String, dynamic>;
      final version = json['version'];
      if (version is! int) throw const FormatException('Missing version');
      if (version != 1) {
        throw const ScaleSettingsException(
          ScaleSettingsFailure.unsupportedVersion,
        );
      }
      if (!json.containsKey('defaultId')) {
        throw const FormatException('Missing defaultId');
      }
      return ScaleSettings(
        profiles: (json['profiles'] as List).map((dynamic item) {
          final profile = item as Map<String, dynamic>;
          final serial = profile['serial'] as Map<String, dynamic>;
          return ScaleProfile(
            id: profile['id'] as String,
            alias: profile['alias'] as String,
            port: profile['port'] as String,
            systemId: profile['systemId'] as String,
            model: ScaleModel.values.byName(profile['model'] as String),
            serial: ScaleSerialSettings(
              baudRate: serial['baudRate'] as int,
              dataBits: serial['dataBits'] as int,
              parity: serial['parity'] as int,
              stopBits: serial['stopBits'] as int,
            ),
          );
        }),
        defaultId: json['defaultId'] as String?,
      );
    } on ScaleSettingsException {
      rethrow;
    } catch (_) {
      throw const ScaleSettingsException(ScaleSettingsFailure.corrupt);
    }
  }

  @override
  Future<void> saveSettings(ScaleSettings settings) => _serialize(() async {
    try {
      final file = await _file();
      // An ordinary save cannot overwrite corruption discovered since load.
      await _read(file);
      await _replace(file, settings);
    } on ScaleSettingsException {
      rethrow;
    } catch (_) {
      throw const ScaleSettingsException(ScaleSettingsFailure.writeFailed);
    }
  });

  @override
  Future<String> recoverSettings() => _serialize(() async {
    try {
      final file = await _file();
      try {
        await _read(file);
        throw StateError('Recovery requires an invalid format');
      } on ScaleSettingsException catch (error) {
        if (!error.canRecover) rethrow;
      }
      final archive = '${file.path}.preserved-${_suffix()}';
      await file.copy(archive);
      await _replace(file, ScaleSettings(profiles: const []));
      return archive;
    } catch (_) {
      throw const ScaleSettingsException(ScaleSettingsFailure.writeFailed);
    }
  });

  String _suffix() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Future<void> _replace(File file, ScaleSettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${_suffix()}.tmp');
    try {
      final json = {
        'version': 1,
        'profiles': [
          for (final profile in settings.profiles)
            {
              'id': profile.id,
              'alias': profile.alias,
              'port': profile.port,
              'systemId': profile.systemId,
              'model': profile.model.name,
              'serial': {
                'baudRate': profile.serial.baudRate,
                'dataBits': profile.serial.dataBits,
                'parity': profile.serial.parity,
                'stopBits': profile.serial.stopBits,
              },
            },
        ],
        'defaultId': settings.defaultId,
      };
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      // Same-directory replacement; never delete the confirmed file first.
      await temporary.rename(file.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Cleanup cannot turn a committed replacement into a failed save.
      }
    }
  }
}
