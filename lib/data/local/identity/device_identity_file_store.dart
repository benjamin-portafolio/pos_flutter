import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../application/identity/device_identity_provider.dart';

typedef DeviceIdentityDirectoryProvider = Future<Directory> Function();
typedef DeviceIdGenerator = String Function();

class DeviceIdentityFileStore implements DeviceIdentityProvider {
  DeviceIdentityFileStore({
    DeviceIdentityDirectoryProvider? directoryProvider,
    DeviceIdGenerator? idGenerator,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _idGenerator = idGenerator ?? _defaultDeviceId;

  static const _fileName = 'device_identity.txt';
  static const _uuid = Uuid();

  final DeviceIdentityDirectoryProvider _directoryProvider;
  final DeviceIdGenerator _idGenerator;

  @override
  Future<String> getDeviceId() async {
    final file = await _identityFile();
    final storedDeviceId = await _readStoredDeviceId(file);
    if (storedDeviceId != null) return storedDeviceId;

    final deviceId = _idGenerator();
    await file.writeAsString('$deviceId\n', flush: true);
    return deviceId;
  }

  Future<File> _identityFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }

  Future<String?> _readStoredDeviceId(File file) async {
    if (!await file.exists()) return null;

    final value = (await file.readAsString()).trim();
    if (value.isEmpty) return null;
    return value;
  }

  static String _defaultDeviceId() => 'device_${_uuid.v4()}';
}
