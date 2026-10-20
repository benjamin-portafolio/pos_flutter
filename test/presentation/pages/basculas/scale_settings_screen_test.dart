import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_device.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/application/weighing/scale_settings_exception.dart';
import 'package:pos_flutter/data/weighing/rhino_bar8rs_protocol.dart';
import 'package:pos_flutter/presentation/pages/basculas/scale_settings_screen.dart';
import 'package:pos_flutter/presentation/pages/basculas/scale_test_screen.dart';

import '../../../support/fake_scale_gateway.dart';
import '../../../support/fake_scale_settings_store.dart';

void main() {
  late FakeScaleGateway gateway;
  late FakeScaleSettingsStore store;
  late ScaleSessionService service;
  late ScaleSettingsController controller;
  final a = ScaleProfile(
    id: 'a',
    alias: 'Caja A',
    port: 'COM8',
    systemId: 'pnp-a',
  );
  final b = ScaleProfile(
    id: 'b',
    alias: 'Caja B',
    port: 'COM9',
    systemId: 'pnp-b',
  );
  const device = ScaleDevice(
    port: 'COM8',
    name: 'USB serial',
    systemId: 'pnp-a',
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScaleSettingsScreen(
          controller: controller,
          gateway: gateway,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> choosePort(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  void scaleTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      gateway = FakeScaleGateway()..devices = [device];
      store = FakeScaleSettingsStore();
      service = ScaleSessionService(gateway);
      controller = ScaleSettingsController(
        store,
        sessionService: () => service,
      );
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      try {
        await body(tester);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        gateway.failClose = false;
        final closing = service.active?.close();
        if (gateway.pendingOpen?.isCompleted == false) {
          gateway.pendingOpen!.complete();
        }
        if (gateway.pendingClose?.isCompleted == false) {
          gateway.pendingClose!.complete();
        }
        for (final pending in gateway.reads) {
          if (!pending.isCompleted) pending.complete([]);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await closing;
        await service.dispose();
        await controller.dispose();
        await tester.binding.setSurfaceSize(null);
      }
    });
  }

  scaleTest(
    'B10/B11 explicit enumeration, required alias/port, only Rhino; canceled add is inert',
    (tester) async {
      await open(tester);
      expect(gateway.calls, isEmpty);
      await tap(tester, 'Agregar báscula');
      await tap(tester, 'Guardar');
      expect(find.text('Escribe un alias.'), findsOneWidget);
      expect(find.text('Selecciona un puerto.'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<ScaleModel>>(
              find.byType(DropdownButton<ScaleModel>),
            )
            .items,
        hasLength(1),
      );
      await tap(tester, 'Actualizar puertos');
      expect(gateway.calls, ['list']);
      await choosePort(tester, 'COM8 · USB serial');
      await tester.enterText(find.byType(TextFormField).first, ' Caja nueva ');
      await tap(tester, 'Cancelar');
      expect(controller.settings.profiles, isEmpty);
      expect(store.saves, 0);
      expect(gateway.calls, ['list']);
    },
  );

  scaleTest('B10 add test close save explicit default edit and remove', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Agregar báscula');
    await tap(tester, 'Actualizar puertos');
    await choosePort(tester, 'COM8 · USB serial');
    await tester.enterText(find.byType(TextFormField).first, ' Caja nueva ');
    await tap(tester, 'Probar lectura');
    expect(find.text('Prueba de lectura'), findsOneWidget);
    expect(controller.settings.profiles, isEmpty);
    gateway.reads.single.complete(
      RhinoBar8RsProtocol().add('  0.278 kg\r'.codeUnits),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('0.278 kg'), findsOneWidget);
    expect(store.saves, 0);
    await tap(tester, 'Cerrar prueba');
    expect(service.active, isNull);
    await tap(tester, 'Guardar');
    expect(controller.settings.profiles.single.alias, 'Caja nueva');
    expect(controller.settings.defaultId, isNull);
    await tap(tester, 'Elegir predeterminada');
    await tap(tester, 'Editar');
    await tester.enterText(find.byType(TextFormField).first, 'Editada');
    await tap(tester, 'Guardar');
    expect(controller.settings.profiles.single.alias, 'Editada');
    await tap(tester, 'Dejar sin predeterminada');
    expect(controller.settings.defaultId, isNull);
    await tap(tester, 'Elegir predeterminada');
    await tap(tester, 'Quitar');
    await tap(tester, 'Quitar');
    expect(controller.settings.profiles, isEmpty);
    expect(controller.settings.defaultId, isNull);
    expect(gateway.calls.where((c) => c.startsWith('open')), hasLength(1));
  });

  scaleTest('B12/B13 several profiles change default, remove leaves none', (
    tester,
  ) async {
    await controller.upsert(a);
    await controller.upsert(b);
    await open(tester);
    await tap(tester, 'Elegir predeterminada');
    expect(controller.settings.defaultId, 'b');
    final firstCard = find.byKey(const ValueKey('a'));
    await tester.tap(
      find.descendant(
        of: firstCard,
        matching: find.text('Elegir predeterminada'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.settings.defaultId, 'a');
    await tester.tap(
      find.descendant(of: firstCard, matching: find.text('Quitar')),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Quitar');
    expect(controller.settings.profiles.single.id, 'b');
    expect(controller.settings.defaultId, isNull);
  });

  scaleTest('B11 duplicate destination cannot be added', (tester) async {
    await controller.upsert(a);
    await open(tester);
    await tap(tester, 'Agregar báscula');
    await tap(tester, 'Actualizar puertos');
    await choosePort(tester, 'COM8 · USB serial');
    await tester.enterText(find.byType(TextFormField).first, 'Duplicada');
    await tap(tester, 'Guardar');
    expect(find.text('Ese puerto ya tiene un perfil.'), findsOneWidget);
    expect(controller.settings.profiles, hasLength(1));
  });

  scaleTest(
    'B15 renumbered port requires explicit reselection and never opens',
    (tester) async {
      await controller.upsert(a);
      gateway.devices = [
        const ScaleDevice(port: 'COM15', name: 'USB serial', systemId: 'pnp-a'),
      ];
      await open(tester);
      await tap(tester, 'Editar');
      await tap(tester, 'Actualizar puertos');
      expect(
        find.textContaining('Selecciona el puerto explícitamente'),
        findsOneWidget,
      );
      await tap(tester, 'Guardar');
      expect(find.text('Selecciona un puerto.'), findsOneWidget);
      expect(controller.settings.profiles.single.port, 'COM8');
      await choosePort(tester, 'COM15 · USB serial');
      await tap(tester, 'Guardar');
      expect(controller.settings.profiles.single.port, 'COM15');
      expect(gateway.calls, ['list']);
    },
  );

  scaleTest(
    'B15/B07 edit delete and test report busy without retargeting sale',
    (tester) async {
      await controller.upsert(a);
      gateway.pendingOpen = Completer<void>();
      final sale = service.open(a, owner: ScaleSessionOwner.sale);
      await open(tester);
      await tap(tester, 'Editar');
      expect(find.textContaining('Ocupada.'), findsWidgets);
      await tap(tester, 'Quitar');
      expect(find.text('Quitar báscula'), findsNothing);
      await tap(tester, 'Probar lectura');
      expect(find.textContaining('Ocupada.'), findsWidgets);
      await tap(tester, 'Cerrar prueba');
      expect(service.active, same(sale));
      expect(sale.profile, same(a));
      expect(controller.settings.profiles.single, same(a));
      expect(gateway.calls, ['open:COM8']);
    },
  );

  scaleTest(
    'B07 back during pending open waits for close and drops late samples',
    (tester) async {
      await controller.upsert(a);
      gateway.pendingOpen = Completer<void>();
      gateway.pendingClose = Completer<void>();
      await open(tester);
      await tap(tester, 'Probar lectura');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ScaleTestScreen), findsOneWidget);
      expect(service.active, isNotNull);
      gateway.pendingOpen!.complete();
      await tester.pump();
      expect(gateway.calls, ['open:COM8', 'close']);
      expect(service.active, isNotNull);
      gateway.pendingClose!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ScaleTestScreen), findsNothing);
      expect(service.active, isNull);
    },
  );

  scaleTest(
    'B07 failed close keeps route and reservation until explicit retry',
    (tester) async {
      await controller.upsert(a);
      await open(tester);
      await tap(tester, 'Probar lectura');
      gateway.failClose = true;
      await tester.tap(find.text('Cerrar prueba'));
      await tester.pump();
      gateway.reads.single.complete(
        RhinoBar8RsProtocol().add('  1.076 kg\r'.codeUnits),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.076 kg'), findsNothing);
      expect(find.textContaining('No se confirmó el cierre'), findsOneWidget);
      expect(service.active, isNotNull);
      gateway.failClose = false;
      await tap(tester, 'Cerrar prueba');
      expect(service.active, isNull);
      expect(find.byType(ScaleTestScreen), findsNothing);
    },
  );

  for (final interruption in ['activity', 'focus', 'route']) {
    scaleTest(
      'B07 $interruption invalidates weight and requires explicit fresh restart',
      (tester) async {
        await controller.upsert(a);
        await open(tester);
        await tap(tester, 'Probar lectura');
        gateway.reads.single.complete(
          RhinoBar8RsProtocol().add('  0.278 kg\r'.codeUnits),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('0.278 kg'), findsOneWidget);
        if (interruption == 'activity') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else if (interruption == 'focus') {
          tester.binding.handleViewFocusChanged(
            ViewFocusEvent(
              viewId: tester.view.viewId,
              state: ViewFocusState.unfocused,
              direction: ViewFocusDirection.undefined,
            ),
          );
        } else {
          unawaited(
            Navigator.of(tester.element(find.byType(ScaleTestScreen))).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Otra ruta')),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(service.active, isNull);
        if (interruption == 'activity') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else if (interruption == 'focus') {
          tester.binding.handleViewFocusChanged(
            ViewFocusEvent(
              viewId: tester.view.viewId,
              state: ViewFocusState.focused,
              direction: ViewFocusDirection.undefined,
            ),
          );
        } else {
          Navigator.of(tester.element(find.text('Otra ruta'))).pop();
        }
        await tester.pumpAndSettle();
        expect(find.text('0.278 kg'), findsNothing);
        expect(gateway.calls.where((c) => c.startsWith('open')), hasLength(1));
        await tap(tester, 'Reanudar prueba');
        expect(gateway.calls.where((c) => c.startsWith('open')), hasLength(2));
        expect(find.text('0.278 kg'), findsNothing);
      },
    );
  }

  scaleTest(
    'B14 failed write preserves confirmed profiles and recovery is explicit',
    (tester) async {
      await controller.upsert(a);
      await open(tester);
      store.writeError = const ScaleSettingsException(
        ScaleSettingsFailure.writeFailed,
      );
      await tap(tester, 'Elegir predeterminada');
      expect(controller.settings.defaultId, isNull);
      expect(find.textContaining('último estado confirmado'), findsOneWidget);
      store.writeError = null;
      store.readError = const ScaleSettingsException(
        ScaleSettingsFailure.corrupt,
      );
      await controller.load();
      await tester.pumpAndSettle();
      await tap(tester, 'Recuperar configuración');
      await tap(tester, 'Cancelar');
      expect(controller.settings.profiles.single, same(a));
      await tap(tester, 'Recuperar configuración');
      await tap(tester, 'Conservar y reiniciar');
      expect(controller.settings.profiles, isEmpty);
      expect(find.textContaining('Original conservado en:'), findsOneWidget);
    },
  );

  scaleTest('B08 unsupported platform informs without opening any port', (
    tester,
  ) async {
    gateway.listFailure = ScaleFailure.unsupportedPlatform;
    await open(tester);
    await tap(tester, 'Agregar báscula');
    await tap(tester, 'Actualizar puertos');
    expect(find.textContaining('disponible en Windows'), findsWidgets);
    expect(gateway.calls, ['list']);
  });

  scaleTest(
    'B07 external removal closes pending reading and ignores late weight',
    (tester) async {
      await controller.upsert(a);
      await open(tester);
      await tap(tester, 'Probar lectura');
      await tester.pumpWidget(const SizedBox());
      expect(service.active, isNotNull);
      gateway.reads.single.complete(
        RhinoBar8RsProtocol().add('  1.076 kg\r'.codeUnits),
      );
      await tester.pump();
      await tester.pump();
      expect(service.active, isNull);
      expect(gateway.calls, ['open:COM8', 'query', 'close']);
      expect(tester.takeException(), isNull);
    },
  );
}
