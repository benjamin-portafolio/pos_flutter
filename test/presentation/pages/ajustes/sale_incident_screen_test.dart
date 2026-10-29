import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_incident_screen.dart';
import '../../../application/commands/ventas/sale_reconciliation_test.dart'
    show ReconciliationHarness;

void main() {
  testWidgets(
    'tablet incidencia muestra evidencia, confirma y conserva estado pendiente',
    (tester) async {
      await tester.runAsync(() async {
        final x = await ReconciliationHarness.create();
        addTearDown(x.h.close);
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final icons = Platform.environment['POS_SESSION4_ICONS'];
        if (icons != null) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(
                  ByteData.sublistView(await File(icons).readAsBytes()),
                ),
              ))
              .load();
        }
        final font = Platform.environment['POS_SESSION4_FONT'];
        if (font != null) {
          await (FontLoader('TabletQA')..addFont(
                Future.value(
                  ByteData.sublistView(await File(font).readAsBytes()),
                ),
              ))
              .load();
        }
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'TabletQA'),
            home: RepaintBoundary(
              key: key,
              child: SaleIncidentScreen(
                incidentId: x.incidentId,
                commands: x.commands,
                adjustments: x.h.store,
                cash: x.h.cashStore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Ganador oficial:'), findsOneWidget);
        expect(find.textContaining('Local ya realizado'), findsOneWidget);
        final field = find.widgetWithText(
          TextField,
          'Motivo y justificación de las diferencias',
        );
        await tester.ensureVisible(field);
        await tester.enterText(
          field,
          'Reconozco exceso físico local documentado.',
        );
        await tester.ensureVisible(find.text('Revisar conciliación'));
        await tester.tap(find.text('Revisar conciliación'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Reconocimiento independiente:'),
          findsOneWidget,
        );
        final directory = Platform.environment['POS_SESSION4_VISUAL_DIR'];
        if (directory != null) {
          await tester.drag(find.byType(ListView), const Offset(0, 800));
          await tester.pumpAndSettle();
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/incident-1280x900.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.pumpAndSettle();
        if (directory != null) {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/incident-bottom-1280x900.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        final commit = find.text('Registrar conciliación');
        await tester.ensureVisible(commit);
        await tester.tap(commit);
        await tester.pumpAndSettle();
        expect(find.textContaining('Conciliación registrada:'), findsOneWidget);
        expect(await x.h.store.hasIncident(x.saleId), true);
        expect(
          (await x.persistence.pendingEvents()).where(
            (e) => e.eventType == 'operacion_venta_conciliada',
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
