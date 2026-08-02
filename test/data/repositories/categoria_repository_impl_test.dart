import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late AppDatabase db;
  late CategoriaRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = CategoriaRepositoryImpl(categoriaDao: CategoriaDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  test('obtiene y mapea categorias desde Drift', () async {
    await _insertarCategoria(
      db,
      id: 'categoria-1',
      name: 'Bebidas',
      colorKey: 'blue',
      sortOrder: 1,
    );

    final categorias = await repository.obtenerCategorias();

    expect(categorias, hasLength(1));
    expect(categorias.single.id, 'categoria-1');
    expect(categorias.single.nombre, 'Bebidas');
    expect(categorias.single.color, ColorCategoria.blue);
    expect(categorias.single.orden, 1);
  });

  test('no usa active para ocultar categorias', () async {
    await _insertarCategoria(
      db,
      id: 'categoria-inactiva',
      name: 'Inactiva',
      colorKey: 'neutral',
      sortOrder: 0,
      active: false,
    );

    final categorias = await repository.obtenerCategorias();

    expect(categorias, hasLength(1));
    expect(categorias.single.id, 'categoria-inactiva');
  });

  test('observa categorias ordenadas por posicion y nombre', () async {
    await _insertarCategoria(
      db,
      id: 'categoria-2',
      name: 'Comida',
      colorKey: 'orange',
      sortOrder: 2,
    );
    await _insertarCategoria(
      db,
      id: 'categoria-1',
      name: 'Bebidas',
      colorKey: 'blue',
      sortOrder: 1,
    );

    final categorias = await repository.watchCategorias().first;

    expect(categorias.map((categoria) => categoria.id), [
      'categoria-1',
      'categoria-2',
    ]);
  });

  test(
    'usa id como desempate estable para una misma posicion y nombre',
    () async {
      await _insertarCategoria(
        db,
        id: 'categoria-2',
        name: 'Duplicada',
        colorKey: 'blue',
        sortOrder: 0,
      );
      await _insertarCategoria(
        db,
        id: 'categoria-1',
        name: 'Duplicada',
        colorKey: 'neutral',
        sortOrder: 0,
      );

      final categorias = await repository.obtenerCategorias();

      expect(categorias.map((categoria) => categoria.id), [
        'categoria-1',
        'categoria-2',
      ]);
    },
  );
}

Future<void> _insertarCategoria(
  AppDatabase db, {
  required String id,
  required String name,
  required String colorKey,
  required int sortOrder,
  bool active = true,
}) {
  return db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          active: Value(active),
          name: name,
          colorKey: Value(colorKey),
          sortOrder: sortOrder,
        ),
      );
}
