import 'dart:async';

import 'package:pos_flutter/application/weighing/scale_settings.dart';
import 'package:pos_flutter/application/weighing/scale_settings_exception.dart';
import 'package:pos_flutter/application/weighing/scale_settings_store.dart';

class FakeScaleSettingsStore implements ScaleSettingsStore {
  ScaleSettings settings = ScaleSettings(profiles: const []);
  ScaleSettingsException? readError;
  ScaleSettingsException? writeError;
  Completer<void>? pendingWrite;
  int saves = 0;

  @override
  Future<ScaleSettings> readSettings() async {
    if (readError case final error?) throw error;
    return settings;
  }

  @override
  Future<void> saveSettings(ScaleSettings next) async {
    saves++;
    await pendingWrite?.future;
    if (writeError case final error?) throw error;
    settings = next;
  }

  @override
  Future<String> recoverSettings() async {
    if (writeError case final error?) throw error;
    readError = null;
    settings = ScaleSettings(profiles: const []);
    return 'preserved.json';
  }
}
