import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/eliminar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/caja/draft_item_edit_sheet.dart';

import '../../../support/fake_unidad_inventario_repository.dart';
import '../../../support/sale_draft_fixtures.dart';

void main() {
  Future<EditingCommands> pumpSheet(
    WidgetTester tester,
    SaleDraftItem item, {
    FakeUnidadInventarioRepository? units,
  }) async {
    final commands = EditingCommands();
    await tester.pumpWidget(
      MaterialApp(home: _Host(item: item, commands: commands, units: units)),
    );
    await tester.pumpAndSettle();
    return commands;
  }

  final piece = sampleSale().items.first; // 2 × $42.00 = $84.00
  final measured = measuredSaleItem; // 0.750 kg × $200 / 1 kg = $15000

  testWidgets('muestra título, precio, cantidad y controles del modo', (
    tester,
  ) async {
    await pumpSheet(tester, sampleSale().items.last);
    expect(find.text('Editar Test Variantes · Variante 2'), findsOneWidget);
    expect(find.text('Precio de venta'), findsOneWidget);
    expect(find.text(r'$21.00'), findsOneWidget);
    expect(find.text('Cantidad'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Disminuir cantidad'), findsOneWidget);
    expect(find.byTooltip('Aumentar cantidad'), findsOneWidget);
    expect(find.byTooltip('Eliminar artículo'), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.text('Aplicar oferta'), findsOneWidget);
    final offer = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(offer.onChanged, isNull);
    final update = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Actualizar artículo'),
    );
    expect(update.onPressed, isNull); // Sin cambios: deshabilitado.
    expect(tester.takeException(), isNull);
  });

  testWidgets('+ habilita actualizar, aplica la cantidad y cierra el panel', (
    tester,
  ) async {
    final commands = await pumpSheet(tester, piece);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    final update = find.widgetWithText(FilledButton, 'Actualizar artículo');
    expect(tester.widget<FilledButton>(update).onPressed, isNotNull);
    await tester.tap(update);
    await tester.pumpAndSettle();
    expect(commands.updated, hasLength(1));
    expect(commands.updated.single.saleItemId, piece.id);
    expect(commands.updated.single.quantity, 3);
    expect(find.byType(DraftItemEditSheet), findsNothing);
  });

  testWidgets('cantidad inválida deshabilita actualizar y muestra error', (
    tester,
  ) async {
    final commands = await pumpSheet(tester, piece);
    final field = find.byKey(const Key('draft_item_quantity_field'));
    await tester.enterText(field, '0');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Actualizar artículo'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Ingresa una cantidad mayor que cero.'),
      findsOneWidget,
    );
    await tester.enterText(field, '-3');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Actualizar artículo'),
          )
          .onPressed,
      isNull,
    );
    expect(commands.updated, isEmpty);
  });

  testWidgets('cerrar sin actualizar descarta los cambios', (tester) async {
    final commands = await pumpSheet(tester, piece);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(DraftItemEditSheet), findsNothing);
    expect(commands.updated, isEmpty);
    expect(commands.removed, isEmpty);
  });

  testWidgets('− al llegar a cero confirma; cancelar conserva el producto', (
    tester,
  ) async {
    final commands = await pumpSheet(tester, piece); // parte de 2
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar artículo?'), findsOneWidget);
    expect(
      find.text('Test Variantes será eliminado de esta venta.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(DraftItemEditSheet), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(commands.removed, isEmpty);
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('− al llegar a cero y confirmar elimina y cierra', (
    tester,
  ) async {
    final commands = await pumpSheet(tester, piece);
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pump();
    await tester.tap(find.byTooltip('Disminuir cantidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(commands.removed, hasLength(1));
    expect(commands.removed.single.saleItemId, piece.id);
    expect(find.byType(DraftItemEditSheet), findsNothing);
  });

  testWidgets('papelera elimina la línea tras confirmar', (tester) async {
    final commands = await pumpSheet(tester, piece);
    await tester.tap(find.byTooltip('Eliminar artículo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar artículo?'), findsOneWidget);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(commands.removed, hasLength(1));
    expect(find.byType(DraftItemEditSheet), findsNothing);
    expect(commands.updated, isEmpty);
  });

  testWidgets('línea medida muestra unidad y + suma la referencia del precio', (
    tester,
  ) async {
    final commands = await pumpSheet(
      tester,
      measured,
      units: FakeUnidadInventarioRepository(),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.750'), findsOneWidget);
    expect(find.text(r'$200.00 / 1 kg'), findsOneWidget);
    final field = find.byKey(const Key('draft_item_quantity_field'));
    expect(tester.widget<TextField>(field).decoration?.suffixText, 'kg');
    await tester.tap(find.byTooltip('Aumentar cantidad'));
    await tester.pump();
    expect(find.text('1.750'), findsOneWidget);
    final update = find.widgetWithText(FilledButton, 'Actualizar artículo');
    expect(tester.widget<FilledButton>(update).onPressed, isNotNull);
    await tester.tap(update);
    await tester.pumpAndSettle();
    expect(commands.updated.single.measuredQuantity, '1.750');
    expect(commands.updated.single.quantity, isNull);
  });

  testWidgets('medida inválida deshabilita actualizar con mensaje de error', (
    tester,
  ) async {
    final commands = await pumpSheet(
      tester,
      measured,
      units: FakeUnidadInventarioRepository(),
    );
    final field = find.byKey(const Key('draft_item_quantity_field'));
    // Más decimales de los permitidos: el formatter rechaza la escritura.
    await tester.enterText(field, '0.0001');
    await tester.pump();
    expect(find.text('0.750'), findsOneWidget);
    // Una magnitud dentro del formato pero igual a cero no se guarda.
    await tester.enterText(field, '0.000');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Actualizar artículo'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('La cantidad debe ser mayor que cero.'),
      findsOneWidget,
    );
    expect(commands.updated, isEmpty);
  });

  testWidgets('− se deshabilita cuando la medida no alcanza el paso', (
    tester,
  ) async {
    await pumpSheet(tester, measured, units: FakeUnidadInventarioRepository());
    final minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(minus.onPressed, isNull); // 0.750 − 1 kg sería negativo.
  });
}

class _Host extends StatefulWidget {
  const _Host({
    required this.item,
    required this.commands,
    this.units,
  });
  final SaleDraftItem item;
  final EditingCommands commands;
  final FakeUnidadInventarioRepository? units;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: DraftItemEditSheet(
              item: widget.item,
              ventaBorradorCommandService: widget.commands,
              unidadInventarioRepository: widget.units,
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

class EditingCommands implements VentaBorradorCommandService {
  final updated = <ActualizarProductoBorradorCommand>[];
  final removed = <EliminarProductoBorradorCommand>[];
  Object? failWith;

  @override
  Future<void> actualizarProducto(
    ActualizarProductoBorradorCommand command,
  ) async {
    updated.add(command);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> eliminarProducto(EliminarProductoBorradorCommand command) async {
    removed.add(command);
    if (failWith != null) throw failWith!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}