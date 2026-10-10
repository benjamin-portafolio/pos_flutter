import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/printing/printer_profile.dart';
import '../../../application/printing/printer_settings.dart';
import '../../../application/printing/printer_settings_exception.dart';
import '../../../application/printing/printer_settings_store.dart';

class PrinterSettingsFileStore implements PrinterSettingsStore {
  PrinterSettingsFileStore({Future<Directory> Function()? directoryProvider})
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
      File(p.join((await _directoryProvider()).path, 'printer_settings.json'));

  @override
  Future<PrinterSettings> readSettings() => _serialize(() async {
    try {
      return await _read(await _file());
    } on PrinterSettingsException {
      rethrow;
    } catch (_) {
      throw const PrinterSettingsException(PrinterSettingsFailure.readFailed);
    }
  });

  Future<PrinterSettings> _read(File file) async {
    if (!await file.exists()) return PrinterSettings(printers: const []);
    // I/O errors are distinct from invalid JSON and must not offer a reset.
    final contents = await file.readAsBytes();
    try {
      final json = jsonDecode(utf8.decode(contents)) as Map<String, dynamic>;
      final version = json['version'];
      if (version is! int) throw const FormatException('Missing version');
      if (version != 1) {
        throw const PrinterSettingsException(
          PrinterSettingsFailure.unsupportedVersion,
        );
      }
      if (!json.containsKey('defaultAddress')) {
        throw const FormatException('Missing defaultAddress');
      }
      return PrinterSettings(
        printers: (json['printers'] as List).map((dynamic item) {
          final profile = item as Map<String, dynamic>;
          return PrinterProfile(
            address: profile['address'] as String,
            alias: profile['alias'] as String,
            paper: PrinterPaper.values.byName(profile['paper'] as String),
            printableWidthDots: profile['printableWidthDots'] as int,
            imageCommand: PrinterImageCommand.values.byName(
              profile['imageCommand'] as String,
            ),
            supportsCut: profile['supportsCut'] as bool,
          );
        }),
        defaultAddress: json['defaultAddress'] as String?,
      );
    } on PrinterSettingsException {
      rethrow;
    } catch (_) {
      throw const PrinterSettingsException(PrinterSettingsFailure.corrupt);
    }
  }

  @override
  Future<void> saveSettings(PrinterSettings settings) => _serialize(() async {
    try {
      final file = await _file();
      // Never overwrite a damaged/unknown format through an ordinary save.
      await _read(file);
      await _replace(file, settings);
    } on PrinterSettingsException {
      rethrow;
    } catch (_) {
      throw const PrinterSettingsException(PrinterSettingsFailure.writeFailed);
    }
  });

  @override
  Future<String> recoverSettings() => _serialize(() async {
    try {
      final file = await _file();
      try {
        await _read(file);
        throw StateError('Recovery requires an invalid format');
      } on PrinterSettingsException catch (error) {
        if (!error.canRecover) rethrow;
      }
      final archive = '${file.path}.preserved-${_suffix()}';
      await file.copy(archive);
      await _replace(file, PrinterSettings(printers: const []));
      return archive;
    } catch (_) {
      throw const PrinterSettingsException(PrinterSettingsFailure.writeFailed);
    }
  });

  String _suffix() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Future<void> _replace(File file, PrinterSettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${_suffix()}.tmp');
    try {
      final json = {
        'version': 1,
        'printers': [
          for (final profile in settings.printers)
            {
              'address': profile.address,
              'alias': profile.alias,
              'paper': profile.paper.name,
              'printableWidthDots': profile.printableWidthDots,
              'imageCommand': profile.imageCommand.name,
              'supportsCut': profile.supportsCut,
            },
        ],
        'defaultAddress': settings.defaultAddress,
      };
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      // Same-directory rename replaces the destination without deleting it first.
      await temporary.rename(file.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Cleanup cannot turn an already committed replacement into a failure.
      }
    }
  }
}
