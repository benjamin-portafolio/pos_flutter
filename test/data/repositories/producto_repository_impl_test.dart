import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late AppDatabase db;
  late ProductoRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ProductoRepositoryImpl(productoDao: ProductoDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'agrupa un solo join, filtra activos y ordena productos y variantes',
    () async {
      await _insertCategory(
        db,
        id: 'category-drinks',
        name: 'Bebidas',
        colorKey: 'blue',
      );
      await _insertProduct(
        db,
        id: 'product-z',
        name: 'Beta',
        categoryId: 'category-drinks',
      );
      await _insertVariant(
        db,
        id: 'variant-z-2',
        productId: 'product-z',
        price: 5200,
        isDefault: true,
        sortOrder: 2,
      );
      await _insertVariant(
        db,
        id: 'variant-z-0',
        productId: 'product-z',
        price: 5000,
        isDefault: false,
        sortOrder: 0,
      );
      await _insertVariant(
        db,
        id: 'variant-z-1-inactive',
        productId: 'product-z',
        price: 5100,
        isDefault: false,
        sortOrder: 1,
        active: false,
      );
      await _insertProduct(db, id: 'product-b', name: 'Alfa');
      await _insertVariant(
        db,
        id: 'variant-b',
        productId: 'product-b',
        price: 2500,
        isDefault: true,
        sortOrder: 0,
      );
      await _insertProduct(db, id: 'product-a', name: 'Alfa');
      await _insertVariant(
        db,
        id: 'variant-a',
        productId: 'product-a',
        price: 2000,
        isDefault: true,
        sortOrder: 0,
      );
      await _insertProduct(
        db,
        id: 'product-inactive',
        name: 'Oculto',
        active: false,
      );
      await _insertVariant(
        db,
        id: 'variant-inactive-product',
        productId: 'product-inactive',
        price: 1000,
        isDefault: true,
        sortOrder: 0,
      );

      final articles = await repository.watchArticulos().first;

      expect(articles.map((article) => article.productoId), [
        'product-a',
        'product-b',
        'product-z',
      ]);
      final beta = articles.last;
      expect(beta.categoriaNombre, 'Bebidas');
      expect(beta.categoriaColor, ColorCategoria.blue);
      expect(beta.variantePredeterminadaId, 'variant-z-2');
      expect(beta.precioPredeterminadoMenor, 5200);
      expect(beta.variantesActivas.map((variant) => variant.varianteId), [
        'variant-z-0',
        'variant-z-2',
      ]);
      expect(
        beta.variantesActivas.every((variant) => variant.nombre == null),
        isTrue,
      );
    },
  );

  test(
    'combina búsqueda con categorías mediante AND y alternativas con OR',
    () async {
      for (final id in ['category-1', 'category-2', 'category-3']) {
        await _insertCategory(db, id: id, name: id, colorKey: 'neutral');
      }
      await _insertSimpleArticle(
        db,
        id: 'coffee-1',
        name: 'Café americano',
        categoryId: 'category-1',
      );
      await _insertSimpleArticle(
        db,
        id: 'tea-2',
        name: 'Té verde',
        categoryId: 'category-2',
      );
      await _insertSimpleArticle(db, id: 'coffee-none', name: 'Café de olla');
      await _insertSimpleArticle(
        db,
        id: 'cake-3',
        name: 'Pastel',
        categoryId: 'category-3',
      );

      final alternatives = await repository
          .watchArticulos(
            categoriaIds: const {'category-1', 'category-2'},
            incluirSinCategoria: true,
          )
          .first;
      expect(alternatives.map((article) => article.productoId).toSet(), {
        'coffee-1',
        'tea-2',
        'coffee-none',
      });

      final intersection = await repository
          .watchArticulos(
            busqueda: '  CAFÉ ',
            categoriaIds: const {'category-1', 'category-2'},
            incluirSinCategoria: true,
          )
          .first;
      expect(intersection.map((article) => article.productoId).toSet(), {
        'coffee-1',
        'coffee-none',
      });
    },
  );

  test('trata comodines de LIKE como texto de búsqueda literal', () async {
    await _insertSimpleArticle(db, id: 'percent', name: 'Descuento 10%');
    await _insertSimpleArticle(db, id: 'plain', name: 'Descuento normal');

    final articles = await repository.watchArticulos(busqueda: '%').first;

    expect(articles.map((article) => article.productoId), ['percent']);
  });

  test('obtiene productos activos e inactivos sin contar variantes', () async {
    await _insertCategory(
      db,
      id: 'category-count',
      name: 'Conteo',
      colorKey: 'amber',
    );
    await _insertProduct(
      db,
      id: 'product-active',
      name: 'Activo',
      categoryId: 'category-count',
    );
    await _insertProduct(
      db,
      id: 'product-inactive',
      name: 'Inactivo',
      categoryId: 'category-count',
      active: false,
    );
    await _insertVariant(
      db,
      id: 'variant-1',
      productId: 'product-active',
      price: 1000,
      isDefault: true,
      sortOrder: 0,
    );
    await _insertVariant(
      db,
      id: 'variant-2',
      productId: 'product-active',
      price: 2000,
      isDefault: false,
      sortOrder: 1,
    );

    final linked = await repository.obtenerArticulosPorCategoria(
      'category-count',
    );
    expect(linked.map((article) => article.productoId), [
      'product-active',
      'product-inactive',
    ]);
    expect(linked.map((article) => article.activo), [true, false]);
  });

  test('emite automáticamente después de un commit local', () async {
    final expectation = expectLater(
      repository.watchArticulos(),
      emitsInOrder([
        isEmpty,
        predicate<List<Object?>>((items) => items.length == 1),
      ]),
    );
    await Future<void>.delayed(Duration.zero);

    await db.transaction(() async {
      await _insertProduct(db, id: 'product-new', name: 'Nuevo');
      await _insertVariant(
        db,
        id: 'variant-new',
        productId: 'product-new',
        price: 3200,
        isDefault: true,
        sortOrder: 0,
      );
    });

    await expectation;
  });

  test('mapea nombres y costos reales de las variantes', () async {
    await _insertProduct(db, id: 'named-product', name: 'Café');
    await _insertVariant(
      db,
      id: 'named-variant',
      productId: 'named-product',
      name: 'Grande',
      nameKey: 'grande',
      price: 1000,
      standardCost: 200,
      isDefault: true,
      sortOrder: 0,
    );

    final articles = await repository.watchArticulos().first;
    final variant = articles.single.variantesActivas.single;
    expect(variant.nombre, 'Grande');
    expect(variant.costoEstandarMenor, 200);
  });

  test(
    'una proyección activa sin predeterminada válida produce error',
    () async {
      await _insertProduct(db, id: 'invalid-product', name: 'Inválido');
      await _insertVariant(
        db,
        id: 'invalid-variant',
        productId: 'invalid-product',
        price: 1000,
        isDefault: false,
        sortOrder: 0,
      );

      await expectLater(
        repository.watchArticulos(),
        emitsError(isA<StateError>()),
      );
    },
  );
}

Future<void> _insertCategory(
  AppDatabase db, {
  required String id,
  required String name,
  required String colorKey,
}) {
  return db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          name: name,
          colorKey: Value(colorKey),
          sortOrder: 0,
        ),
      );
}

Future<void> _insertProduct(
  AppDatabase db, {
  required String id,
  required String name,
  String? categoryId,
  bool active = true,
}) {
  return db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: name,
          categoryId: Value(categoryId),
          active: Value(active),
        ),
      );
}

Future<void> _insertVariant(
  AppDatabase db, {
  required String id,
  required String productId,
  required int price,
  String? name,
  String? nameKey,
  int? standardCost,
  required bool isDefault,
  required int sortOrder,
  bool active = true,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productId,
          name: Value(name),
          nameKey: Value(nameKey),
          salePriceMinor: price,
          standardCostMinor: Value(standardCost),
          isDefault: isDefault,
          sortOrder: sortOrder,
          active: Value(active),
        ),
      );
}

Future<void> _insertSimpleArticle(
  AppDatabase db, {
  required String id,
  required String name,
  String? categoryId,
}) {
  return db.transaction(() async {
    await _insertProduct(db, id: id, name: name, categoryId: categoryId);
    await _insertVariant(
      db,
      id: 'variant-$id',
      productId: id,
      price: 1000,
      isDefault: true,
      sortOrder: 0,
    );
  });
}
