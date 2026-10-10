import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_gate.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_probe_screen.dart';

import '../../../../support/fake_mobile_scanner_platform.dart';

void main() {
  late MobileScannerPlatform original;
  late FakeMobileScannerPlatform camera;
  late Duration now;
  late BarcodeReadGate gate;
  final navigator = GlobalKey<NavigatorState>();
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
    now = Duration.zero;
    gate = BarcodeReadGate(clock: () => now);
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
  });

  Future<void> open(
    WidgetTester tester,
    Future<String> Function(String) onRead,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BarcodeReadProbeScreen(onRead: onRead, readGate: gate),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    if (camera.startGate == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> emit(WidgetTester tester, List<String> codes) async {
    camera.captures.add(
      BarcodeCapture(
        barcodes: codes.map((code) => Barcode(rawValue: code)).toList(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'normal, 200ms, marco nativo; normaliza y serializa guardado lento',
    (tester) async {
      final pending = Completer<String>();
      final reads = <String>[];
      await open(tester, (code) {
        reads.add(code);
        return pending.future;
      });
      expect(camera.lastStartOptions!.detectionSpeed, DetectionSpeed.normal);
      expect(camera.lastStartOptions!.detectionTimeoutMs, 200);
      expect(
        camera.lastStartOptions!.formats,
        isNot(contains(BarcodeFormat.qrCode)),
      );
      expect(camera.lastScanWindow, isNotNull);
      expect(camera.lastScanWindow!.width, lessThan(1));
      expect(camera.lastScanWindow!.height, lessThan(1));
      await emit(tester, [' ０１２３４５６７８９０５ ', '012345678905']);
      for (var i = 1; i <= 100; i++) {
        now = Duration(milliseconds: i * 200);
        await emit(tester, ['012345678905']);
      }
      expect(reads, ['012345678905']);
      pending.complete('Guardado');
      await tester.pumpAndSettle();
      now += const Duration(milliseconds: 200);
      await emit(tester, ['012345678905']);
      expect(reads, ['012345678905']);
      expect(find.text('Guardado'), findsOneWidget);
    },
  );

  testWidgets(
    'silencio sin callbacks vacíos: tres presentaciones y A → B → A',
    (tester) async {
      final reads = <String>[];
      await open(tester, (code) async {
        reads.add(code);
        return 'Aceptado';
      });
      for (var i = 0; i < 3; i++) {
        await emit(tester, ['001']);
        await emit(tester, ['001']);
        now += const Duration(milliseconds: 1100);
      }
      expect(reads, ['001', '001', '001']);
      await emit(tester, ['002']);
      await emit(tester, ['001']);
      expect(reads, ['001', '001', '001', '002', '001']);
    },
  );

  testWidgets(
    'ambigüedad e inválidos no ejecutan; un error no repite la presentación',
    (tester) async {
      var reads = 0;
      await open(tester, (_) async {
        reads++;
        throw StateError('Fallo');
      });
      await emit(tester, ['001', '002']);
      expect(reads, 0);
      expect(
        find.text('Enfoca un solo código dentro del marco.'),
        findsOneWidget,
      );
      await emit(tester, ['ABC']);
      await emit(tester, ['ABC']);
      expect(reads, 0);
      expect(
        find.text('El código debe tener hasta 32 dígitos.'),
        findsOneWidget,
      );
      await emit(tester, ['001']);
      await emit(tester, ['001']);
      expect(reads, 1);
      expect(find.textContaining('No se pudo procesar'), findsOneWidget);
    },
  );

  testWidgets(
    'ambigüedad durante guardado observa presencia y muestra aviso al liberarse',
    (tester) async {
      var reads = 0;
      final pending = Completer<String>();
      await open(tester, (_) {
        reads++;
        return pending.future;
      });
      await emit(tester, ['001']);
      for (var i = 1; i <= 10; i++) {
        now = Duration(milliseconds: i * 200);
        await emit(tester, ['001', '002']);
      }
      pending.complete('Guardado');
      await tester.pumpAndSettle();
      await emit(tester, ['001', '002']);
      expect(
        find.text('Enfoca un solo código dentro del marco.'),
        findsOneWidget,
      );
      await emit(tester, ['001']);
      expect(reads, 1);
    },
  );

  testWidgets(
    'un diálogo que cancela suspende cámara y no rearma al regresar',
    (tester) async {
      var reads = 0;
      await open(tester, (_) async {
        reads++;
        await showDialog<void>(
          context: navigator.currentContext!,
          builder: (context) => AlertDialog(
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
        return 'Cancelado';
      });
      await emit(tester, ['001']);
      await tester.pumpAndSettle();
      expect(camera.stops, 1);
      now += const Duration(minutes: 1);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await emit(tester, ['001']);
      expect(reads, 1);
      expect(camera.starts, 2);
    },
  );

  testWidgets(
    'cambio de ruta y segundo plano preservan protección sin frames ocultos',
    (tester) async {
      var reads = 0;
      await open(tester, (_) async {
        reads++;
        return 'Guardado';
      });
      await emit(tester, ['001']);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Otra ruta')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      now += const Duration(minutes: 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await emit(tester, ['001']);
      expect(reads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      now += const Duration(minutes: 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await emit(tester, ['001']);
      expect(reads, 1);
      expect(camera.starts, 3);
    },
  );

  testWidgets('cerrar y reabrir con la misma compuerta no acredita retirada', (
    tester,
  ) async {
    var reads = 0;
    await open(tester, (_) async {
      reads++;
      return 'Guardado';
    });
    await emit(tester, ['001']);
    await tester.tap(find.byKey(const Key('close_read_probe')));
    await tester.pumpAndSettle();
    now += const Duration(minutes: 1);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await emit(tester, ['001']);
    expect(reads, 1);
    await emit(tester, ['002']);
    expect(reads, 2);
  });

  testWidgets('cerrar espera guardado y descarta callbacks antiguos', (
    tester,
  ) async {
    var reads = 0;
    final pending = Completer<String>();
    await open(tester, (_) {
      reads++;
      return pending.future;
    });
    final callback = tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect!;
    await emit(tester, ['001']);
    await tester.tap(find.byKey(const Key('close_read_probe')));
    await tester.pump();
    expect(find.text('Esperando la operación para cerrar…'), findsOneWidget);
    callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
    expect(reads, 1);
    pending.complete('Guardado');
    await tester.pumpAndSettle();
    expect(find.byType(BarcodeReadProbeScreen), findsNothing);
    callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '003')]));
    expect(reads, 1);
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
  });

  testWidgets(
    'cierre con permiso pendiente libera cámara al acabar el inicio',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester, (_) async => 'Guardado');
      await tester.tap(find.byKey(const Key('close_read_probe')));
      await tester.pumpAndSettle();
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.stops, 1);
      expect(camera.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('permiso denegado permite cerrar sin aceptar lecturas', (
    tester,
  ) async {
    camera.startError = const MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    );
    var reads = 0;
    await open(tester, (_) async {
      reads++;
      return 'Guardado';
    });
    expect(find.textContaining('Revisa el permiso'), findsOneWidget);
    await emit(tester, ['001']);
    expect(reads, 0);
    await tester.tap(find.byKey(const Key('close_read_probe')));
    await tester.pumpAndSettle();
    expect(find.byType(BarcodeReadProbeScreen), findsNothing);
  });
}
