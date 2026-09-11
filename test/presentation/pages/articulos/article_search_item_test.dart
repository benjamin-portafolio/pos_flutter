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

  test('ordena por creación descendente y después por orden de variante', () {
    expect(search('  '), ['tea-large', 'small', 'large', 'bread-plain']);
    expect(coffee.variantesActivas.first.varianteId, 'large');
  });

  test('el nombre del producto encuentra todas sus variantes', () {
    expect(search('CAFÉ'), ['small', 'large']);
    expect(search('caf'), ['small', 'large']);
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
