import 'scale_profile.dart';

/// Installation-local configuration. A saved destination is not a connection.
class ScaleSettings {
  ScaleSettings({required Iterable<ScaleProfile> profiles, String? defaultId})
    : profiles = List.unmodifiable(profiles),
      defaultId = defaultId?.trim() {
    final ids = this.profiles.map((p) => p.id).toSet();
    final ports = this.profiles.map((p) => p.port).toSet();
    if (ids.length != this.profiles.length ||
        ports.length != this.profiles.length ||
        (this.defaultId != null && !ids.contains(this.defaultId))) {
      throw ArgumentError('Duplicate scale destination/id or absent default');
    }
  }

  final List<ScaleProfile> profiles;
  final String? defaultId;
}
