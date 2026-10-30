import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/eliminar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/caja/draft_item_inline_editor.dart';

import '../../../support/fake_unidad_inventario_repository.dart';
import '../../../support/sale_draft_fixtures.dart';

void main() {
  final piece = sampleSale().items.first;
  Future<EditingCommands> pumpEditor(
    WidgetTester tester, {
    SaleDraftItem? item,
    EditingCommands? commands,
    VoidCallback? onClose,
    ValueChanged<bool>? onSavingChanged,
  }) async {
    final service = commands ?? EditingCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: DraftItemInlineEditor(
              item: item ?? piece,
              ventaBorradorCommandService: service,
              unidadInventarioRepository: FakeUnidadInventarioRepository(),
              onClose: onClose ?? () {},
              onSavingChanged: onSavingChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('controles inline sin panel, oferta ni ventana', (tester) async {
    await pumpEditor(tester);
    expect(find.byTooltip('Disminuir cantidad'), findsOneWidget);
    expect(find.byTooltip('Aumentar cantidad'), findsOneWidget);
    expect(find.byTooltip('Eliminar artículo'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Aplicar cantidad'), findsNothing);
  });

  testWidgets('+ y − guardan inmediatamente y mantienen la edición', (
    tester,
  ) async {
    var closed = false;
    final commands = await pumpEditor(tester, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pumpAndSettle();
    expect(commands.updated.single.quantity, 3);
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pumpAndSettle();
    expect(commands.updated.last.quantity, 2);
    expect(commands.updated.last.saleItemId, piece.id);
    expect(closed, isFalse);
  });

  testWidgets('cantidad manual se guarda sin confirmación y Enter no duplica', (
    tester,
  ) async {
    final commands = await pumpEditor(tester);
    final field = find.byKey(const Key('draft_item_quantity_field'));
    await tester.enterText(field, '7');
    await tester.pumpAndSettle();
    expect(commands.updated.single.quantity, 7);
    expect(find.text('Aplicar cantidad'), findsNothing);
    await tester.enterText(field, '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commands.updated.last.quantity, 9);
    expect(commands.updated, hasLength(2));
  });

  testWidgets(
    'permite seguir escribiendo durante el guardado sin perder foco',
    (tester) async {
      final gate = Completer<void>();
      final commands = EditingCommands()..gate = gate.future;
      await pumpEditor(tester, commands: commands);
      final field = find.byType(TextField);
      await tester.enterText(field, '7');
      await tester.pump();
      await tester.enterText(field, '75');
      await tester.pump();
      expect(commands.updated.single.quantity, 7);
      expect(tester.widget<TextField>(field).enabled, isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(commands.updated.map((command) => command.quantity), [7, 75]);
      expect(find.text('75'), findsOneWidget);
    },
  );

  testWidgets('cantidad por medida escrita se guarda sin confirmación', (
    tester,
  ) async {
    final commands = await pumpEditor(tester, item: measuredSaleItem);
    await tester.enterText(find.byType(TextField), '1.250');
    await tester.pumpAndSettle();
    expect(commands.updated.single.measuredQuantity, '1.250');
    expect(commands.updated.single.quantity, isNull);
    expect(find.text('Aplicar cantidad'), findsNothing);
  });

  testWidgets('cero e inválidos no se guardan', (tester) async {
    final commands = await pumpEditor(tester);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(find.text('Ingresa una cantidad mayor que cero.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commands.updated, isEmpty);
    expect(find.text('Aplicar cantidad'), findsNothing);
  });

  testWidgets('− hasta cero confirma en la fila; cancelar conserva cantidad', (
    tester,
  ) async {
    final commands = await pumpEditor(tester);
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pumpAndSettle();
    expect(commands.updated.single.quantity, 1);
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar artículo?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(commands.removed, isEmpty);
  });

  testWidgets('papelera confirma y elimina con el comando existente', (
    tester,
  ) async {
    var closed = false;
    final commands = await pumpEditor(tester, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Eliminar artículo'));
    await tester.pump();
    expect(commands.removed, isEmpty);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(commands.removed.single.saleItemId, piece.id);
    expect(closed, isTrue);
  });

  testWidgets('medidas conservan unidad, precisión y paso de referencia', (
    tester,
  ) async {
    final commands = await pumpEditor(tester, item: measuredSaleItem);
    expect(find.text('0.750'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.suffixText,
      'kg',
    );
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pumpAndSettle();
    expect(commands.updated.single.measuredQuantity, '1.750');
    expect(commands.updated.single.quantity, isNull);
    await tester.enterText(find.byType(TextField), '0.0001');
    await tester.pump();
    expect(find.text('1.750'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0.000');
    await tester.pump();
    expect(find.text('La cantidad debe ser mayor que cero.'), findsOneWidget);
    expect(commands.updated, hasLength(1));
  });

  testWidgets('fallo conserva cantidad para reintento explícito', (
    tester,
  ) async {
    final commands = EditingCommands()..failWith = StateError('fallo');
    await pumpEditor(tester, commands: commands);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pumpAndSettle();
    expect(find.text('fallo'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    commands.failWith = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(commands.updated, hasLength(2));
    expect(commands.updated.last.quantity, 3);
  });

  testWidgets('guardado bloquea dobles toques y libera estado al desmontarse', (
    tester,
  ) async {
    final gate = Completer<void>();
    final states = <bool>[];
    final commands = EditingCommands()..gate = gate.future;
    await pumpEditor(tester, commands: commands, onSavingChanged: states.add);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pump();
    expect(commands.updated, hasLength(1));
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(states, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edición y confirmación caben en 320 px con texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    await tester.tap(find.byTooltip('Eliminar artículo'));
    await tester.pump();
    expect(find.text('¿Eliminar artículo?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class EditingCommands implements VentaBorradorCommandService {
  final updated = <ActualizarProductoBorradorCommand>[];
  final removed = <EliminarProductoBorradorCommand>[];
  Object? failWith;
  Future<void>? gate;

  @override
  Future<void> actualizarProducto(
    ActualizarProductoBorradorCommand command,
  ) async {
    updated.add(command);
    if (failWith != null) throw failWith!;
    await gate;
  }

  @override
  Future<void> eliminarProducto(EliminarProductoBorradorCommand command) async {
    removed.add(command);
    if (failWith != null) throw failWith!;
    await gate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
