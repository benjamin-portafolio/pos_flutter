import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_service.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_transport.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_baseline_bootstrap_installer.dart';

class _Transport implements BaselineBootstrapTransport {
  _Transport(this.manifest, this.chunks);
  final Map<String, Object?> manifest;
  final List<List<int>> chunks;
  int calls = 0;
  bool loseBindingResponse = false;
  final downloaded = <int>[];
  @override
  Future<List<int>> descriptor() async {
    calls++;
    return utf8.encode(recoveryCanonical(manifest));
  }

  @override
  Future<List<int>> chunk(int i) async {
    calls++;
    downloaded.add(i);
    return chunks[i];
  }

  @override
  Future<Map<String, Object?>> bind(String dataset, String digest) async {
    calls++;
    if (loseBindingResponse) {
      loseBindingResponse = false;
      throw const SocketException('lost binding response');
    }
    return {
      'server_instance_id': manifest['server_instance_id'],
      'generation_id': manifest['generation_id'],
      'dataset_id': dataset,
      'baseline_high_watermark': manifest['baseline_high_watermark'],
      'device_id': 'new-device-C',
      'token': 'dedicated-binding',
    };
  }
}

void main() {
  late Directory dir;
  late _Transport transport;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos-bootstrap-s4-test-');
    final source = Directory('test/fixtures/recovery_s3');
    final original =
        jsonDecode(await File('${source.path}/manifest.json').readAsString())
            as Map;
    final chunks = <List<int>>[];
    for (final c in original['chunks'] as List) {
      chunks.add(await File('${source.path}/${c['file']}').readAsBytes());
    }
    final entityRows = <String, List<String>>{};
    for (final bytes in chunks) {
      for (final line in utf8.decode(bytes).trim().split('\n')) {
        final envelope = jsonDecode(line) as Map;
        entityRows
            .putIfAbsent(envelope['entity'] as String, () => [])
            .add(
              recoveryCanonical(
                Map<String, Object?>.from(envelope['row'] as Map),
              ),
            );
      }
    }
    final rowDigests = {
      for (final e in [
        'units',
        'events',
        'event_refs',
        'suppliers',
        'clientes',
      ])
        e: sha256
            .convert(
              utf8.encode((entityRows[e] ?? []).map((x) => '$x\n').join()),
            )
            .toString(),
    };
    transport = _Transport({
      'format': 'pos-baseline-bootstrap/1',
      'bootstrap_version': 1,
      'dataset_id': '10000000-0000-4000-8000-000000000001',
      'server_instance_id': '10000000-0000-4000-8000-000000000002',
      'generation_id': '10000000-0000-4000-8000-000000000003',
      'baseline_high_watermark': '99',
      'summary': {
        'units': '5',
        'events': '1',
        'event_refs': '1',
        'suppliers': '1',
        'clientes': '0',
        'row_digests': rowDigests,
      },
      'chunks': [
        for (final c in original['chunks'] as List)
          {
            'index': c['index'],
            'entity': c['entity'],
            'rows': c['rows'],
            'bytes': c['bytes'],
            'sha256': c['sha256'],
          },
      ],
    }, chunks);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<Map<String, Object?>> install([AppMode mode = AppMode.serverSync]) =>
      BaselineBootstrapService().installEmpty(
        mode: mode,
        expectedServer: transport.manifest['server_instance_id'] as String,
        expectedGeneration: transport.manifest['generation_id'] as String,
        expectedDigest: sha256
            .convert(utf8.encode(recoveryCanonical(transport.manifest)))
            .toString(),
        transport: transport,
        installer: SqliteBaselineBootstrapInstaller(dir),
      );
  test(
    'empty v10 installs evidence once, refs server, identity/checkpoint H; no historical replay or pending',
    () async {
      final result = await install();
      final db = AppDatabase.forTesting(
        NativeDatabase(File(result['database_path'] as String)),
      );
      addTearDown(db.close);
      expect(
        (await db.select(db.suppliers).get()).single.name,
        'Proveedor acreditado',
      );
      final event = (await db.select(db.events).get()).single;
      expect(event.deliveryStatus, 'delivered');
      expect(event.applicationStatus, 'applied');
      expect((await db.select(db.eventRefs).get()).single.source, 'server');
      expect(
        await db.syncCheckpointDao.obtenerLastFullPullServerSequence(),
        99,
      );
      expect(
        await db.syncCheckpointDao.obtenerLastPreflightServerSequence(),
        99,
      );
      expect(
        (await db.select(db.recoveryLocalState).get()).single.generationId,
        transport.manifest['generation_id'],
      );
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      expect(await db.select(db.cashMovements).get(), isEmpty);
    },
  );
  test('standalone stops before network and database creation', () async {
    await expectLater(install(AppMode.standalone), throwsStateError);
    expect(transport.calls, 0);
    expect(await dir.list().toList(), isEmpty);
  });
  test(
    'lost binding response resumes committed local database without downloading or replay',
    () async {
      transport.loseBindingResponse = true;
      await expectLater(install(), throwsA(isA<SocketException>()));
      final caches = (await dir.list().toList())
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('download-'))
          .single;
      final committed =
          jsonDecode(await File('${caches.path}/installed.json').readAsString())
              as Map;
      final downloads = List<int>.from(transport.downloaded);
      final result = await install();
      expect(result['database_path'], committed['database_path']);
      expect(transport.downloaded, downloads);
      final db = AppDatabase.forTesting(
        NativeDatabase(File(result['database_path'] as String)),
      );
      expect(await db.select(db.events).get(), hasLength(1));
      await db.close();
    },
  );
  test(
    'corruption removes only own staging and never sends binding ack',
    () async {
      final original = transport.chunks[3];
      transport.chunks[3] = utf8.encode('corrupt');
      final sentinel = File('${dir.path}/preserve.txt');
      await sentinel.writeAsString('unchanged');
      await expectLater(install(), throwsFormatException);
      expect(await sentinel.readAsString(), 'unchanged');
      final files = await dir.list().toList();
      expect(
        files.whereType<Directory>().every(
          (d) => p.basename(d.path).startsWith('download-'),
        ),
        isTrue,
      );
      expect(transport.calls, 5);
      expect(transport.downloaded, [0, 1, 2, 3]);
      transport.chunks[3] = original;
      await install();
      expect(transport.downloaded, [0, 1, 2, 3, 3, 4]);
    },
  );
}
