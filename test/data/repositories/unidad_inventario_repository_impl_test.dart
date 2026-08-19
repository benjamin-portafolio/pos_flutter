import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  test('devuelve solo unidades activas agrupables por dimensión', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await (db.update(db.units)
          ..where((unit) => unit.unitId.equals(InventoryUnitIds.gram)))
        .write(const UnitsCompanion(active: Value(false)));

    final units = await UnidadInventarioRepositoryImpl(
      unitDao: UnitDao(db),
    ).obtenerUnidadesActivas();

    expect(units, hasLength(4));
    expect(units.map((unit) => unit.code), isNot(contains('g')));
    expect(
      units.map((unit) => unit.code),
      containsAll(['piece', 'kg', 'ml', 'l']),
    );
    expect(units.map((unit) => unit.dimension).toSet(), hasLength(3));
  });
}
