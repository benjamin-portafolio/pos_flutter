import 'scale_exception.dart';
import 'scale_failure.dart';
import 'scale_serial_settings.dart';

enum ScaleModel { rhinoBar8Rs }

/// Immutable destination snapshot. No discovery or connection in construction.
class ScaleProfile {
  factory ScaleProfile({
    required String id,
    required String alias,
    required String port,
    required String systemId,
    ScaleModel model = ScaleModel.rhinoBar8Rs,
    ScaleSerialSettings serial = const ScaleSerialSettings(),
  }) {
    final normalizedPort = port.trim().toUpperCase();
    if (id.trim().isEmpty ||
        alias.trim().isEmpty ||
        !RegExp(r'^COM[1-9][0-9]{0,4}$').hasMatch(normalizedPort) ||
        systemId.trim().isEmpty ||
        !serial.isRhinoCompatible) {
      throw const ScaleException(ScaleFailure.invalidConfiguration);
    }
    return ScaleProfile._(
      id.trim(),
      alias.trim(),
      normalizedPort,
      systemId.trim(),
      model,
      serial,
    );
  }

  const ScaleProfile._(
    this.id,
    this.alias,
    this.port,
    this.systemId,
    this.model,
    this.serial,
  );

  final String id;
  final String alias;
  final String port;
  final String systemId;
  final ScaleModel model;
  final ScaleSerialSettings serial;
}
