import 'dart:async';

import 'scale_profile.dart';
import 'scale_session_service.dart';
import 'scale_settings.dart';
import 'scale_settings_exception.dart';
import 'scale_settings_store.dart';

class ScaleSettingsController {
  ScaleSettingsController(this._store, {required this.sessionService});

  final ScaleSettingsStore _store;
  // Resolve lazily: loading a file does not need the hardware service.
  final ScaleSessionService Function() sessionService;
  final _changes = StreamController<ScaleSettings>.broadcast();
  Future<void> _pending = Future.value();
  ScaleSettings _settings = ScaleSettings(profiles: const []);
  ScaleSettingsException? _loadError;
  bool _loaded = false;
  bool _disposed = false;

  ScaleSettings get settings => _settings;
  ScaleSettingsException? get loadError => _loadError;
  bool get loaded => _loaded;
  bool get canEdit => _loaded && _loadError == null && !_disposed;
  Stream<ScaleSettings> get changes => _changes.stream;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    if (_disposed) return Future.error(StateError('Controller disposed'));
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _serialize(() async {
    try {
      final settings = await _store.readSettings();
      _loadError = null;
      _publish(settings);
    } on ScaleSettingsException catch (error) {
      _loadError = error;
      _publish(_settings);
    }
    _loaded = true;
  });

  Future<void> upsert(ScaleProfile profile) => _save(
    () => ScaleSettings(
      profiles: [
        for (final current in _settings.profiles)
          if (current.id == profile.id) profile else current,
        if (!_settings.profiles.any((p) => p.id == profile.id)) profile,
      ],
      defaultId: _settings.defaultId,
    ),
  );

  Future<void> remove(String id) => _save(
    () => ScaleSettings(
      profiles: _settings.profiles.where((p) => p.id != id.trim()),
      defaultId: _settings.defaultId == id.trim() ? null : _settings.defaultId,
    ),
  );

  Future<void> setDefault(String? id) =>
      _save(() => ScaleSettings(profiles: _settings.profiles, defaultId: id));

  Future<void> _save(ScaleSettings Function() next) => _serialize(() async {
    if (!_loaded || _loadError != null) {
      throw StateError('Load or recover scale settings first');
    }
    await sessionService().withIdleResource(() async {
      final settings = next();
      try {
        await _store.saveSettings(settings);
      } on ScaleSettingsException catch (error) {
        if (error.canRecover) _loadError = error;
        rethrow;
      }
      _publish(settings);
    });
  });

  Future<String> recover() => _serialize(() async {
    if (!(_loadError?.canRecover ?? false)) {
      throw StateError('No damaged settings to recover');
    }
    return sessionService().withIdleResource(() async {
      final archive = await _store.recoverSettings();
      _loadError = null;
      _loaded = true;
      _publish(ScaleSettings(profiles: const []));
      return archive;
    });
  });

  void _publish(ScaleSettings settings) {
    _settings = settings;
    if (!_changes.isClosed) _changes.add(settings);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending;
    await _changes.close();
  }
}
