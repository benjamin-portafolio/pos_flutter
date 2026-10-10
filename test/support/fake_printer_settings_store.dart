import 'dart:async';

import 'package:pos_flutter/application/printing/printer_settings.dart';
import 'package:pos_flutter/application/printing/printer_settings_exception.dart';
import 'package:pos_flutter/application/printing/printer_settings_store.dart';

class FakePrinterSettingsStore implements PrinterSettingsStore {
  PrinterSettings settings = PrinterSettings(printers: const []);
  PrinterSettingsException? readError;
  bool failWrite = false;
  int writes = 0;
  int recoveries = 0;
  Completer<void>? pendingWrite;

  @override
  Future<PrinterSettings> readSettings() async {
    if (readError case final error?) throw error;
    return settings;
  }

  @override
  Future<void> saveSettings(PrinterSettings next) async {
    writes++;
    await pendingWrite?.future;
    if (failWrite) {
      throw const PrinterSettingsException(PrinterSettingsFailure.writeFailed);
    }
    settings = next;
  }

  @override
  Future<String> recoverSettings() async {
    recoveries++;
    if (failWrite) {
      throw const PrinterSettingsException(PrinterSettingsFailure.writeFailed);
    }
    settings = PrinterSettings(printers: const []);
    readError = null;
    return '/local/printer_settings.json.preserved-test';
  }
}
