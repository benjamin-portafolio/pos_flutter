import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../support/fake_printer_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const printing = MethodChannel('pos/bluetooth_printer');
  late Directory directory;
  late AppConfig config;
  late FakePrinterGateway gateway;
  var nativeCalls = 0;
  final profile = PrinterProfile(
    address: 'AA:BB:CC:DD:EE:01',
    alias: 'DI test',
    paper: PrinterPaper.mm58,
    printableWidthDots: 384,
    imageCommand: PrinterImageCommand.gsV0,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_printing_di_');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    nativeCalls = 0;
    messenger.setMockMethodCallHandler(printing, (_) async {
      nativeCalls++;
      return null;
    });
    gateway = FakePrinterGateway();
  });
  tearDown(() async {
    gateway.pendingWrite = null;
    gateway.pendingClose = null;
    gateway.closeFailure = null;
    if (getIt.isRegistered<AppDatabase>()) await getIt<AppDatabase>().close();
    if (getIt.isRegistered<AppConfigController>()) {
      await getIt<AppConfigController>().dispose();
    }
    await getIt.reset();
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(printing, null);
    await directory.delete(recursive: true);
  });
  Future<void> setup(AppMode mode) async {
    config = AppConfig.initial.copyWith(
      mode: mode,
      setupCompleted: true,
      backupProvider: BackupProvider.none,
    );
    await AppConfigFileStore().saveConfig(config);
    await setupDependencyInjection();
    expect(nativeCalls, 0);
    await getIt.unregister<PrinterGateway>();
    getIt.registerSingleton<PrinterGateway>(gateway);
  }

  Future<List<Object?>> snapshot(AppDatabase db) async => [
    for (final table in db.allTables)
      (await db.customSelect('SELECT * FROM "${table.actualTableName}"').get())
          .map((r) => r.data)
          .toList(),
  ];
  for (final mode in AppMode.values) {
    test(
      'shared printing in ${mode.name}: no startup Bluetooth/network or database changes',
      () async {
        var networkCalls = 0;
        await HttpOverrides.runZoned(
          () async {
            await setup(mode);
            if (mode == AppMode.standalone) {
              await startConfiguredRuntimeServices(config);
            }
            final db = getIt<AppDatabase>();
            final before = await snapshot(db);
            final settings = getIt<PrinterSettingsController>();
            expect(settings.loaded, isTrue);
            expect(gateway.calls, isEmpty);
            await settings.upsert(profile);
            await settings.setDefault(profile.address);
            final service = getIt<TicketPrintService>();
            expect(getIt<TicketPrintService>(), same(service));
            expect((await service.printTest(profile)).sent, isTrue);
            expect(await snapshot(db), before);
            expect(nativeCalls, 0);
          },
          createHttpClient: (_) {
            networkCalls++;
            throw StateError('Printing must not start synchronization');
          },
        );
        expect(networkCalls, 0);
      },
    );
  }
  for (final mode in AppMode.values) {
    test(
      'printer file survives actual SQLite restore and DI restart in ${mode.name}',
      () async {
        await setup(mode);
        final settings = getIt<PrinterSettingsController>();
        await settings.upsert(profile);
        final backup = await getIt<DatabaseSnapshotService>().createSnapshot();
        final second = PrinterProfile(
          address: 'AA:BB:CC:DD:EE:02',
          alias: 'B80',
          paper: PrinterPaper.mm80,
          printableWidthDots: 576,
          imageCommand: PrinterImageCommand.gsL,
        );
        await settings.upsert(second);
        await settings.setDefault(second.address);
        final file = File('${directory.path}/printer_settings.json');
        final committed = await file.readAsBytes();
        await getIt<DatabaseRestoreService>().restoreSnapshot(
          backup.file,
          sha256: backup.sha256,
        );
        expect(await file.readAsBytes(), committed);
        // Avoid starting unrelated backup/server runtime services in this fixture.
        await AppConfigFileStore().saveConfig(
          config.copyWith(setupCompleted: false),
        );
        await getIt<AppConfigController>().dispose();
        await restartDependencyInjection(previousConfig: config);
        final reloaded = getIt<PrinterSettingsController>();
        expect(reloaded, isNot(same(settings)));
        expect(reloaded.settings.printers.map((p) => p.alias), [
          profile.alias,
          'B80',
        ]);
        expect(reloaded.settings.printers.last.paper, PrinterPaper.mm80);
        expect(reloaded.settings.defaultAddress, second.address);
        expect(await file.readAsBytes(), committed);
        expect(gateway.calls, ['close']);
        expect(nativeCalls, 0);
        await backup.file.parent.delete(recursive: true);
      },
    );
  }
  test('DI reset drains real shared service before replacing gateway', () async {
    await setup(AppMode.standalone);
    gateway.pendingWrite = Completer<void>();
    gateway.pendingClose = Completer<void>();
    final original = getIt<TicketPrintService>();
    // The preexisting reader enables Google Drive in standalone. Keep that
    // scheduler out of this fixture when restart loads the saved config.
    await AppConfigFileStore().saveConfig(
      config.copyWith(setupCompleted: false),
    );
    final first = original.printTest(profile);
    // The production raster is asynchronous. Wait for the native write,
    // rather than assuming a single microtask generates the calibration ticket.
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return gateway.writes.isEmpty;
    }).timeout(const Duration(seconds: 5));
    // Close unrelated existing resources explicitly; reset(dispose:false) is
    // preexisting behavior for them and is outside this feature's scope.
    await getIt<AppDatabase>().close();
    await getIt<AppConfigController>().dispose();
    var replaced = false;
    final restarting = restartDependencyInjection(
      previousConfig: config,
    ).then((_) => replaced = true);
    await Future<void>.delayed(Duration.zero);
    expect(
      (await original.printTest(profile)).failure,
      PrinterFailure.disposed,
    );
    gateway.pendingWrite!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(replaced, isFalse);
    expect(getIt<TicketPrintService>(), same(original));
    gateway.pendingClose!.complete();
    await first;
    await restarting;
    expect(replaced, isTrue);
    expect(getIt<TicketPrintService>(), isNot(same(original)));
    expect(gateway.writes, hasLength(1));
    expect(nativeCalls, 0);
  });
  test('failed close blocks reset and keeps old gateway owned', () async {
    await setup(AppMode.standalone);
    final original = getIt<TicketPrintService>();
    gateway.closeFailure = PrinterFailure.closeFailed;
    await expectLater(
      restartDependencyInjection(previousConfig: config),
      throwsA(isA<PrinterException>()),
    );
    expect(getIt<TicketPrintService>(), same(original));
    expect(getIt<PrinterGateway>(), same(gateway));
  });
}
