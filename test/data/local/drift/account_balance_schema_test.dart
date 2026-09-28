import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

const insert = '''
  INSERT INTO account_balance_baselines(id,device_id,declared_by_user_id,amount_minor,as_of_ms,created_event_id,last_event_id)''';

void main() {
  test('el saldo admite negativo y respeta el rango seguro', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Una cuenta sobregirada es una declaración legítima: es la única
    // divergencia de rango contra el resto del esquema y es deliberada.
    await db.customStatement(
      "$insert VALUES('a','d','u',-7500,1789041600000,'e','e')",
    );
    expect(
      (await db.select(db.accountBalanceBaselines).get()).single.amountMinor,
      -7500,
    );

    for (final invalid in <String>[
      // Fuera del rango del entero seguro, por abajo y por arriba.
      "$insert VALUES('b','d','u',-9007199254740992,1,'e','e')",
      "$insert VALUES('c','d','u',9007199254740992,1,'e','e')",
      // La frontera es un instante: ni cero ni fuera de rango.
      "$insert VALUES('d','d','u',1,0,'e','e')",
      "$insert VALUES('f','d','u',1,9007199254740992,'e','e')",
    ]) {
      await expectLater(db.customStatement(invalid), throwsA(anything));
    }
    expect(await db.select(db.accountBalanceBaselines).get(), hasLength(1));
  });

  test('no hay columna de estado: el hecho no se cierra ni se anota', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final columns = (await db
            .customSelect('PRAGMA table_info(account_balance_baselines)')
            .get())
        .map((row) => row.read<String>('name'));

    expect(
      columns,
      containsAll([
        'id',
        'device_id',
        'declared_by_user_id',
        'amount_minor',
        'as_of_ms',
        'created_event_id',
        'last_event_id',
        'last_server_sequence',
      ]),
    );
    for (final absent in [
      'status',
      'closed_at_ms',
      'counted_minor',
      'close_snapshot',
      'notes',
      'cash',
      'account_id',
    ]) {
      expect(columns, isNot(contains(absent)));
    }

    // `created_event_id` y `last_event_id` quedan igual que en caja: el
    // handler es quien garantiza que se llenen, y sin `last_event_id` no hay
    // join a `events` y por tanto no hay chip de entrega.
    final nullable = (await db
            .customSelect('PRAGMA table_info(account_balance_baselines)')
            .get())
        .where((row) => row.read<int>('notnull') == 0)
        .map((row) => row.read<String>('name'));
    expect(
      nullable,
      containsAll([
        'created_event_id',
        'last_event_id',
        'last_server_sequence',
      ]),
    );
  });

  test('migrar de 7 crea la tabla y conserva lo declarado antes', () async {
    final directory = await Directory.systemTemp.createTemp('pos-schema-v7-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/migration.sqlite');

    // Base en esquema 7: sin la tabla nueva y con una caja ya declarada.
    final previous = AppDatabase.forTesting(NativeDatabase(file));
    await previous.customStatement(
      "INSERT INTO cash_sessions(id,device_id,opened_by_user_id,status,opened_at_ms,opening_minor) VALUES('a','d','u','open',1,100)",
    );
    await previous.customStatement('DROP TABLE account_balance_baselines');
    await previous.customStatement('PRAGMA user_version = 7');
    await previous.close();

    final current = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(current.close);

    final version = (await current
            .customSelect('PRAGMA user_version')
            .get())
        .single
        .read<int>('user_version');
    expect(version, 8);
    // La caja previa sigue intacta: la migracion solo agrega su tabla.
    expect(
      (await current.select(current.cashSessions).get()).single.openingMinor,
      100,
    );
    await current.customStatement(
      "$insert VALUES('11111111-1111-4111-8111-111111111111','d','u',-1,1789041600000,'e','e')",
    );
    expect(await current.select(current.accountBalanceBaselines).get(), hasLength(1));
    await current.close();
  });
}
