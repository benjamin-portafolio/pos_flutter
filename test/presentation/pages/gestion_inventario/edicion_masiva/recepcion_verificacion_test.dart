import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/edicion_masiva/catalogo_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/application/edicion_masiva/lectura_edicion_masiva.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/pantalla_edicion_masiva_por_tarea.dart';

import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  final evidenceFont = Platform.environment['BULK_UI_FONT'];
  setUpAll(() async {
    if (evidenceFont != null) {
      final bytes = await File(evidenceFont).readAsBytes();
      await (FontLoader(
        'BulkEvidence',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  late ProductSupplierHarness h;
  setUp(() => h = ProductSupplierHarness());
  tearDown(() => h.dispose());

  for (final width in [320.0, 360.0, 390.0, 800.0]) {
    testWidgets(
      'M47 accesibilidad en ambas vistas a $width px, texto ampliado y nombres largos',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();

        await seedRecepcion(
          h,
          nombre:
              'Mercancía con nombre largo para comprobar lectura y controles accesibles',
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: evidenceFont == null
                  ? null
                  : ThemeData(fontFamily: 'BulkEvidence'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: PantallaEdicionMasivaPorTarea(
                catalogo: DriftCatalogoEdicionMasiva(h.db),
                comando: coordinadorRecepcion(h),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final compact in [false, true]) {
          if (compact) {
            await tester.tap(find.byKey(const Key('edicion_masiva_vista')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Recepción compacta').last);
            await tester.pumpAndSettle();
          }
          if (compact) {
            final quantity = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is TextField &&
                      widget.key.toString().contains(
                        'edicion_masiva_cantidad_',
                      ),
                )
                .first;
            if (width < 390) {
              expect(tester.getSize(quantity).width, greaterThan(width * .7));
            }
          }
          expect(tester.takeException(), isNull);
          final name = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key.toString().contains('edicion_masiva_nombre_'),
          );
          expect(name, findsWidgets);
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.descendant(
                    of: name.first,
                    matching: find.byType(RichText),
                  ),
                )
                .didExceedMaxLines,
            isFalse,
            reason: 'El nombre largo no debe ocultar la variante al final.',
          );
          expect(
            find.byTooltip('Capturas confirmadas y recuperación'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('Buscar artículo o variante')),
            findsOneWidget,
          );
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          final output = Platform.environment['BULK_UI_EVIDENCE'];
          if (output != null) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              await File(
                '$output/${width.toInt()}-${compact ? 'compacta' : 'tarea'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            });
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'M48 listado real de 10000 variantes limita lecturas y campos construidos',
    (tester) async {
      await seedRecepcion(h, nombre: 'AAA Primer producto');
      await h.db.batch((b) {
        b.insertAll(h.db.products, [
          for (var i = 3; i < 10000; i++)
            ProductsCompanion.insert(id: 'lazy-p-$i', name: 'ZZZ Artículo $i'),
        ]);
        b.insertAll(h.db.productVariants, [
          for (var i = 3; i < 10000; i++)
            ProductVariantsCompanion.insert(
              id: 'lazy-v-$i',
              productId: 'lazy-p-$i',
              salePriceMinor: 2000,
              sortOrder: 0,
            ),
        ]);
      });
      final catalog = _Reads(DriftCatalogoEdicionMasiva(h.db));
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaEdicionMasivaPorTarea(
            catalogo: catalog,
            comando: coordinadorRecepcion(h),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(catalog.pages, [100]);
      expect(catalog.details, 0);
      expect(find.byType(TextField).evaluate().length, lessThan(20));
      expect(find.text('ZZZ Artículo 9999'), findsNothing);
      final before = await fotoRecepcion(h.db);
      await tester.enterText(
        find.byKey(const Key('edicion_masiva_busqueda')),
        '9999',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(catalog.pages, [100, 100]);
      expect(catalog.details, 0);
      expect(await fotoRecepcion(h.db), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Reads implements CatalogoEdicionMasiva {
  _Reads(this.delegate);
  final CatalogoEdicionMasiva delegate;
  final pages = <int>[];
  int details = 0;
  @override
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  }) {
    pages.add(limite);
    return delegate.buscar(
      busqueda: busqueda,
      limite: limite,
      desplazamiento: desplazamiento,
    );
  }

  @override
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  }) {
    details += claves.length;
    return delegate.leer(claves, proveedorIds: proveedorIds);
  }
}
