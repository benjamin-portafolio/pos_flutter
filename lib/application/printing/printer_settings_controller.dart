import 'dart:async';

import 'printer_profile.dart';
import 'printer_settings.dart';
import 'printer_settings_exception.dart';
import 'printer_settings_store.dart';

class PrinterSettingsController {
  PrinterSettingsController(this._store);

  final PrinterSettingsStore _store;
  final _changes = StreamController<PrinterSettings>.broadcast();
  Future<void> _pending = Future.value();
  PrinterSettings _settings = PrinterSettings(printers: const []);
  PrinterSettingsException? _loadError;
  bool _loaded = false;
  bool _disposed = false;

  PrinterSettings get settings => _settings;
  PrinterSettingsException? get loadError => _loadError;
  bool get loaded => _loaded;
  bool get canEdit => _loaded && _loadError == null && !_disposed;
  Stream<PrinterSettings> get changes => _changes.stream;

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
    } on PrinterSettingsException catch (error) {
      _loadError = error;
    }
    _loaded = true;
  });

  Future<void> upsert(PrinterProfile profile) => _save(
    () => PrinterSettings(
      printers: [
        for (final current in _settings.printers)
          if (current.destinationKey == profile.destinationKey)
            profile
          else
            current,
        if (!_settings.printers.any(
          (p) => p.destinationKey == profile.destinationKey,
        ))
          profile,
      ],
      defaultAddress: _settings.defaultAddress,
    ),
  );

  Future<void> remove(String address) => _save(() {
    final name = address.trim();
    final normalized =
        _settings.printers
            .where(
              (p) =>
                  p.destinationKey == address ||
                  (p.transport == PrinterTransport.androidBluetooth &&
                      p.address == name.toUpperCase()),
            )
            .firstOrNull
            ?.destinationKey ??
        name;
    return PrinterSettings(
      printers: _settings.printers.where((p) => p.destinationKey != normalized),
      defaultAddress: _settings.defaultAddress == normalized
          ? null
          : _settings.defaultAddress,
    );
  });

  Future<void> setDefault(String? address) => _save(
    () =>
        PrinterSettings(printers: _settings.printers, defaultAddress: address),
  );

  Future<void> _save(PrinterSettings Function() next) => _serialize(() async {
    if (!_loaded || _loadError != null) {
      throw StateError('Load or recover printer settings first');
    }
    final settings = next(); // Reuse the model's address/default invariants.
    try {
      await _store.saveSettings(settings);
    } on PrinterSettingsException catch (error) {
      // The file may have changed since load. Expose recovery rather than
      // leaving the UI with repeatable save failures and no recovery action.
      if (error.canRecover) _loadError = error;
      rethrow;
    }
    _publish(settings);
  });

  Future<String> recover() => _serialize(() async {
    if (!(_loadError?.canRecover ?? false)) {
      throw StateError('No damaged settings to recover');
    }
    final archive = await _store.recoverSettings();
    _loadError = null;
    _loaded = true;
    _publish(PrinterSettings(printers: const []));
    return archive;
  });

  void _publish(PrinterSettings settings) {
    _settings = settings;
    if (!_changes.isClosed) _changes.add(settings);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending;
    await _changes.close();
  }
}
