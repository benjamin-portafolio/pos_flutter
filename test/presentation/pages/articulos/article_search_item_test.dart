import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/presentation/pages/articulos/models/article_search_item.dart';

void main() {
  final coffee = _article('coffee', 'Café', DateTime(2026, 9, 10), [
    _variant('large', 'Grande', 1),
    _variant('small', 'Chico', 0),
  ]);
  final tea = _article('tea', 'Té', DateTime(2026, 9, 11), [
    _variant('tea-large', 'Grande', 0),
  ]);
  final bread = _article('bread', 'Pan', null, [
    _variant('bread-plain', null, 0),
  ]);
  final catalog = [coffee, bread, tea];

  List<String> search(String query) => ArticleSearchItem.search(
    catalog,
    query,
  ).map((item) => item.variant.varianteId).toList();

  test('código parcial conserva ceros y se habilita explícitamente', () {
    final items = [
      _article('a', 'Pan', null, [
        const VarianteListado(
          varianteId: 'a',
          nombre: 'Integral',
          precioVentaMenor: 100,
          orden: 0,
          codigoBarras: '001234',
        ),
      ]),
    ];
    expect(ArticleSearchItem.search(items, '0012'), isEmpty);
    expect(
      ArticleSearchItem.search(
        items,
        '0012',
        includeBarcode: true,
      ).single.variant.varianteId,
      'a',
    );
    expect(
      ArticleSearchItem.search(items, 'PAN integral 123', includeBarcode: true),
      hasLength(1),
    );
    expect(
      ArticleSearchItem.search(items, '00012', includeBarcode: true),
      isEmpty,
    );
  });

  test('ordena por creación descendente y después por orden de variante', () {
    expect(search('  '), ['tea-large', 'small', 'large', 'bread-plain']);
    expect(coffee.variantesActivas.first.varianteId, 'large');
  });

  test('el nombre del producto encuentra todas sus variantes', () {
    expect(search('CAFÉ'), ['small', 'large']);
    expect(search('cafe'), ['small', 'large']);
    expect(search('te'), ['tea-large']);
    expect(search('caf'), ['small', 'large']);
  });

  test('ignora diacríticos en producto, variante y consulta', () {
    final articles = [
      _article('lemon', 'Limón', null, [
        _variant('cold', 'Frío', 0),
        _variant('natural', 'Natural', 1),
      ]),
      _article('tea', 'Te\u0301', null, [_variant('hot', 'Caliente', 0)]),
    ];

    for (final query in [
      'limon frio',
      'LIMÓN FRÍO',
      'limo\u0301n fri\u0301o',
    ]) {
      expect(
        ArticleSearchItem.search(
          articles,
          query,
        ).map((item) => item.variant.varianteId),
        ['cold'],
        reason: query,
      );
    }
    expect(
      ArticleSearchItem.search(articles, 'te').single.variant.varianteId,
      'hot',
    );
    expect(
      ArticleSearchItem.search(
        articles,
        'limón naturál',
      ).single.variant.varianteId,
      'natural',
    );
    expect(articles.first.nombre, 'Limón');
    expect(articles.first.variantesActivas.first.nombre, 'Frío');
  });

  test('el nombre de variante no incluye las otras variantes del producto', () {
    expect(search('grande'), ['tea-large', 'large']);
  });

  test('combina palabras del producto y de la misma variante', () {
    expect(search('  CAFÉ   gran  '), ['large']);
    expect(search('Grande café'), ['large']);
    expect(search('Cafe\u0301 grande'), ['large']);
    expect(search('café chico grande'), isEmpty);
    expect(search('café té'), isEmpty);
  });

  test('admite variantes sin nombre y trata comodines como texto literal', () {
    expect(search('pan'), ['bread-plain']);
    expect(search('%'), isEmpty);
    expect(search('_'), isEmpty);
    expect(search('inexistente'), isEmpty);
  });

  test('excluye artículos inactivos y resuelve empates de forma estable', () {
    final items = ArticleSearchItem.search([
      _article('b', 'Igual', DateTime(2026), [_variant('vb', null, 0)]),
      _article('a', 'Igual', DateTime(2026), [_variant('va', null, 0)]),
      _article('hidden', 'Oculto', DateTime(2027), [
        _variant('hidden-v', null, 0),
      ], active: false),
    ], '');
    expect(items.map((item) => item.variant.varianteId), ['va', 'vb']);
  });
}

ArticuloListado _article(
  String id,
  String name,
  DateTime? date,
  List<VarianteListado> variants, {
  bool active = true,
}) => ArticuloListado(
  productoId: id,
  nombre: name,
  activo: active,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  fechaCreacion: date,
  variantesActivas: variants,
);

VarianteListado _variant(String id, String? name, int order) => VarianteListado(
  varianteId: id,
  nombre: name,
  precioVentaMenor: 2500,
  orden: order,
);
