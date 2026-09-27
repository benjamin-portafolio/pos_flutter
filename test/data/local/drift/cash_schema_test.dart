import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  test('cash schema guards open session, origins and closed evidence', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO cash_sessions(id,device_id,opened_by_user_id,status,opened_at_ms,opening_minor) VALUES ('a','d','u','open',1,100)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO cash_sessions(id,device_id,opened_by_user_id,status,opened_at_ms,opening_minor) VALUES ('b','d','u','open',1,100)",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO cash_movements(id,session_id,direction,amount_minor) VALUES ('m','a','in',1)",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "UPDATE cash_sessions SET status='closed' WHERE id='a'",
      ),
      throwsA(anything),
    );
    expect(
      (await db.customSelect('SELECT * FROM cash_sessions').get()).length,
      1,
    );
  });
}
