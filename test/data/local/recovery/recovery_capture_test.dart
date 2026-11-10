import 'package:pos_flutter/data/local/recovery/recovery_row_mapper.dart';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/confirmed_sale_line.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_recovery_snapshot.dart';
import 'package:pos_flutter/application/recovery/recovery_package_reader.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_diagnostic.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/application/recovery/recovery_package_service.dart';
import 'package:pos_flutter/application/recovery/recovery_snapshot.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import '../../../support/product_supplier_harness.dart';

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Red no permitida');
  }
}

void _walWriter(List<Object?> args) {
  final db = raw.sqlite3.open(args[0] as String);
  final port = args[1] as SendPort;
  db.execute('PRAGMA busy_timeout=5000');
  try {
    for (var i = 0; i < 200; i++) {
      db.execute('BEGIN IMMEDIATE');
      db.execute('UPDATE suppliers SET name=?,notes=?', ['$i', '$i']);
      db.execute(
        'UPDATE sync_checkpoints SET last_full_pull_server_sequence=?',
        [i + 200],
      );
      db.execute('COMMIT');
      if (i == 0) port.send('started');
      sleep(const Duration(milliseconds: 1));
    }
    port.send('done');
  } catch (error) {
    port.send('$error');
  } finally {
    db.close();
  }
}

void main() {
  late Directory dir;
  late ProductSupplierHarness h;
  late DriftRecoverySnapshotSource source;
  late _NoNetwork network;
  HttpOverrides? prior;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos-recovery-s3-test-');
    h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('${dir.path}/origin.sqlite')),
      ),
      mode: AppMode.serverSync,
    );
    source = DriftRecoverySnapshotSource(h.db);
    await h.supplier('Proveedor acreditado');
    await h.db.customStatement(
      "UPDATE events SET delivery_status='delivered',server_sequence=7,created_at_server=1794153600",
    );
    await h.db.customStatement("UPDATE suppliers SET last_server_sequence=7");
    await h.db.customStatement(
      "UPDATE event_refs SET server_sequence=7,source='server'",
    );
    await h.db.customStatement(
      "INSERT INTO sync_checkpoints(checkpoint_id,last_full_pull_server_sequence,last_full_pull_at,last_preflight_server_sequence) VALUES ('full_pull',12,1794153600,99)",
    );
    await h.db.customStatement('PRAGMA journal_mode=WAL');
    prior = HttpOverrides.current;
    network = _NoNetwork();
    HttpOverrides.global = network;
  });
  tearDown(() async {
    HttpOverrides.global = prior;
    expect(network.attempts, 0);
    await h.dispose();
    await dir.delete(recursive: true);
  });
  Future<RecoverySnapshot> capture({
    AppMode mode = AppMode.serverSync,
    RecoveryCancellation? cancellation,
  }) => source.capture(
    privateDirectory: Directory('${dir.path}/captures'),
    mode: mode,
    deviceId: 'fixture-device',
    appRevision: 'fixture-s3',
    cancellation: cancellation ?? RecoveryCancellation(),
  );
  Future<Object?> contents() async => {
    for (final t in h.db.allTables)
      t.actualTableName:
          (await h.db
                  .customSelect(
                    'SELECT * FROM "${t.actualTableName}" ORDER BY rowid',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
  };
  test(
    'mismo snapshot: origen intacto, WAL, metadata inmutable, chunks reproducibles',
    () async {
      final before = await contents();
      final s = await capture();
      addTearDown(s.close);
      final diagnostic = await RecoveryDiagnostic.inspect(
        s,
        RecoveryCancellation(),
      );
      expect(diagnostic.toJson(), containsPair('admissible', true));
      expect(diagnostic.checkpoint!['last_full_pull_sequence'], '12');
      expect(
        diagnostic.highWatermark,
        99,
      ); // No usar fecha/secuencia de preflight como último pull.
      expect((s.cut['source'] as Map)['generation_id'], isNull);
      expect(await source.hasChangesSince(s), false);
      final output = await RecoveryPackageService().generate(
        s,
        privateDirectory: Directory('${dir.path}/packages'),
        cancellation: RecoveryCancellation(),
      );
      final other = await RecoveryPackageService().generate(
        s,
        privateDirectory: Directory('${dir.path}/other'),
        cancellation: RecoveryCancellation(),
      );
      final files = output.listSync().whereType<File>().toList();
      for (final f in files) {
        expect(
          await File('${other.path}/${f.uri.pathSegments.last}').readAsBytes(),
          await f.readAsBytes(),
        );
      }
      final manifest =
          jsonDecode(await File('${output.path}/manifest.json').readAsString())
              as Map;
      for (final c in manifest['chunks'] as List) {
        final bytes = await File('${output.path}/${c['file']}').readAsBytes();
        expect(sha256.convert(bytes).toString(), c['sha256']);
        expect(bytes.length, c['bytes']);
        expect(utf8.decode(bytes).split('\n').length - 1, c['rows']);
      }
      expect(files.any((f) => f.path.endsWith('.sqlite')), false);
      expect(await contents(), before);
      final target = Platform.environment['POS_RECOVERY_PACKAGE_FIXTURE'];
      if (target != null) {
        await Directory(target).create(recursive: true);
        for (final f in files) {
          await f.copy('$target/${f.uri.pathSegments.last}');
        }
      }
    },
  );
  test(
    'espera transacción en curso; corte excluye escrituras posteriores',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final writing = h.db.transaction(() async {
        await h.db.customStatement(
          "UPDATE suppliers SET name='Antes del corte'",
        );
        started.complete();
        await finish.future;
        await h.db.customStatement(
          "UPDATE sync_checkpoints SET last_full_pull_server_sequence=25",
        );
      });
      await started.future;
      final pending = capture();
      finish.complete();
      await writing;
      final s = await pending;
      addTearDown(s.close);
      await h.db.customStatement(
        "UPDATE suppliers SET name='Después del corte'",
      );
      expect(s.rows('suppliers').single['name'], 'Antes del corte');
      expect(
        s.rows('sync_checkpoints').single['last_full_pull_server_sequence'],
        25,
      );
      expect(await source.hasChangesSince(s), true);
      expect(
        (await RecoveryDiagnostic.inspect(
          s,
          RecoveryCancellation(),
        )).checkpoint!['last_full_pull_sequence'],
        '25',
      );
    },
  );
  test('revisión cubre entrega/checkpoint y rollback no avanza', () async {
    final s = await capture();
    addTearDown(s.close);
    await expectLater(
      h.db.transaction(() async {
        await h.db.customStatement("UPDATE suppliers SET name='rollback'");
        throw StateError('fixture');
      }),
      throwsStateError,
    );
    expect(await source.hasChangesSince(s), false);
    await h.db.customStatement(
      'UPDATE sync_checkpoints SET last_preflight_server_sequence=100',
    );
    expect(await source.hasChangesSince(s), true);
  });
  test(
    'pending, failed, shared not_required, contrato desconocido y dependencia ausente bloquean sin alterar origen',
    () async {
      await h.db.customStatement(
        "UPDATE events SET delivery_status='pending',application_status='failed',event_type='desconocido'",
      );
      await h.db.customStatement(
        "UPDATE suppliers SET last_event_id='ausente'",
      );
      final before = await contents();
      final s = await capture();
      addTearDown(s.close);
      final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
      expect(d.admissible, false);
      expect(
        d.blockers.map((e) => e['code']),
        containsAll([
          'pending',
          'application_failed',
          'missing_event',
          'incompatible_event_contract',
        ]),
      );
      await expectLater(
        RecoveryPackageService().generate(
          s,
          privateDirectory: Directory('${dir.path}/out'),
          cancellation: RecoveryCancellation(),
        ),
        throwsStateError,
      );
      expect(await s.file.exists(), true);
      expect(await contents(), before);
    },
  );
  test(
    'standalone no red, no refs nuevas y no promoción de not_required',
    () async {
      await h.db.customStatement('DELETE FROM event_refs');
      await h.db.customStatement(
        "UPDATE events SET delivery_status='not_required',server_sequence=NULL",
      );
      final before = await contents();
      final s = await capture(mode: AppMode.standalone);
      addTearDown(s.close);
      final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
      expect(d.admissible, false);
      expect(
        d.blockers.map((e) => e['code']),
        containsAll(['standalone_not_supported', 'shared_not_required']),
      );
      await expectLater(
        RecoveryPackageService().generate(
          s,
          privateDirectory: Directory('${dir.path}/out'),
          cancellation: RecoveryCancellation(),
        ),
        throwsStateError,
      );
      expect(await contents(), before);
    },
  );
  test(
    'fallo de espacio y cancelación limpian staging, conservan snapshot y paquete válido',
    () async {
      final before = await contents();
      final s = await capture();
      addTearDown(s.close);
      final service = RecoveryPackageService();
      final token = RecoveryCancellation();
      await expectLater(
        service.generate(
          s,
          privateDirectory: Directory('${dir.path}/failed'),
          cancellation: token,
          writeFile: (f, b) async {
            await f.writeAsBytes(b.take(5).toList());
            throw const FileSystemException('No space left on device');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${dir.path}/failed').listSync(), isEmpty);
      expect(await s.file.exists(), true);
      await expectLater(
        service.generate(
          s,
          privateDirectory: Directory('${dir.path}/cancelled'),
          cancellation: token,
          writeFile: (f, b) async {
            await f.writeAsBytes(b);
            token.cancel();
          },
        ),
        throwsA(isA<RecoveryCancelled>()),
      );
      expect(Directory('${dir.path}/cancelled').listSync(), isEmpty);
      final valid = await service.generate(
        s,
        privateDirectory: Directory('${dir.path}/valid'),
        cancellation: RecoveryCancellation(),
      );
      final manifest = await File('${valid.path}/manifest.json').readAsBytes();
      await expectLater(
        service.generate(
          s,
          privateDirectory: Directory('${dir.path}/valid'),
          cancellation: RecoveryCancellation(),
        ),
        throwsStateError,
      );
      expect(await File('${valid.path}/manifest.json').readAsBytes(), manifest);
      expect(await contents(), before);
    },
  );
  test('cancelación antes de captura no crea archivos', () async {
    final before = await contents();
    final token = RecoveryCancellation()..cancel();
    await expectLater(
      capture(cancellation: token),
      throwsA(isA<RecoveryCancelled>()),
    );
    expect(await contents(), before);
    expect(Directory('${dir.path}/captures').existsSync(), false);
  });

  test(
    'venta/pago originales y snapshot histórico; reabre captura sin leer origen',
    () async {
      await h.commands.crearArticulo(
        const CrearArticuloCommand(nombre: 'Artículo', precioVenta: '25'),
      );
      final variant = (await h.db.select(h.db.productVariants).get()).single;
      final product = (await h.db.select(h.db.products).get()).single;
      final line = ConfirmedSaleLine(
        id: const Uuid().v4(),
        productId: product.id,
        configurationEventId: product.createdEventId!,
        snapshot: SaleItemSnapshot(
          variantId: variant.id,
          productName: 'Artículo histórico',
          saleMode: 'unit',
          quantity: 2,
          measuredQuantityAtomic: null,
          unitPriceMinor: 2500,
          standardCostMinor: null,
          priceReferenceQuantityAtomic: null,
          unitCode: null,
          unitSymbol: null,
          unitAtomicFactor: null,
        ),
        consumptionMode: 'none',
        saleUnitId: null,
        consumptions: [],
      );
      final payload = VentaConfirmadaPayload(
        paymentId: const Uuid().v4(),
        totalMinor: 5000,
        receivedMinor: 10000,
        changeMinor: 5000,
        currency: 'MXN',
        lines: [line],
        dependencyEventIds: [product.createdEventId!],
      );
      final store = DriftLocalEventStore(
        db: h.db,
        eventDao: h.db.eventDao,
        eventRefDao: h.db.eventRefDao,
        appConfigController: h.tracking.config,
        eventProcessor: EventProcessor(
          handlers: {
            VentaConfirmadaPayload.eventType: (e) =>
                DriftConfirmedSaleStore(h.db).apply(e, payload),
          },
        ),
      );
      final event = SyncEvent(
        eventId: const Uuid().v4(),
        aggregateType: 'sale',
        aggregateId: const Uuid().v4(),
        eventType: VentaConfirmadaPayload.eventType,
        deviceId: 'fixture-sale',
        userId: 'fixture-user',
        createdAtLocal: DateTime.utc(2026, 11, 8),
        payload: payload.toJson(),
      );
      await store.appendAndApply(event, refs: payload.refs(event.aggregateId));
      await h.db.customStatement(
        "UPDATE events SET delivery_status='delivered',server_sequence=20+local_sequence,created_at_server=1794153600",
      );
      await h.db.customStatement(
        'UPDATE suppliers SET last_server_sequence=(SELECT server_sequence FROM events WHERE event_id=suppliers.last_event_id)',
      );
      final original = await contents();
      final s = await capture();
      final file = s.file;
      s.close();
      final reopened = await SqliteRecoverySnapshot.open(file);
      addTearDown(reopened.close);
      final d = await RecoveryDiagnostic.inspect(
        reopened,
        RecoveryCancellation(),
      );
      expect(d.blockers, isEmpty);
      final output = await RecoveryPackageService().generate(
        reopened,
        privateDirectory: Directory('${dir.path}/sale'),
        cancellation: RecoveryCancellation(),
      );
      await RecoveryPackageReader().verify(output, RecoveryCancellation());
      final sale = reopened.exportRows('sales').single;
      expect(sale['sale_id'], event.aggregateId);
      expect(sale['total_minor'], '5000');
      final payment = reopened.exportRows('sale_payments').single;
      expect(payment['payment_id'], payload.paymentId);
      expect(payment['received_minor'], '10000');
      expect(payment['change_minor'], '5000');
      final item = reopened.exportRows('sale_items').single;
      expect(
        (item['snapshot'] as Map)['configuration_event_id'],
        product.createdEventId,
      );
      expect((item['snapshot'] as Map)['snapshot'], line.snapshot.toJson());
      expect(
        reopened.exportRows('events').every((e) => e['local_sequence'] == null),
        true,
      );
      expect(await contents(), original);
      await h.db.customStatement(
        "UPDATE sale_items SET created_event_id='70000000-0000-4000-8000-000000000001'",
      );
      final bad = await capture();
      addTearDown(bad.close);
      final invalid = await RecoveryDiagnostic.inspect(
        bad,
        RecoveryCancellation(),
      );
      expect(invalid.blockers.map((b) => b['code']), contains('missing_event'));
      await h.db.customStatement(
        'UPDATE sale_items SET created_event_id=?,unit_price_minor=2499',
        [event.eventId],
      );
      final mismatched = await capture();
      addTearDown(mismatched.close);
      final mismatch = await RecoveryDiagnostic.inspect(
        mismatched,
        RecoveryCancellation(),
      );
      expect(
        mismatch.blockers.any(
          (b) =>
              b['code'] == 'unexportable_entity' &&
              jsonEncode(b['path']).contains(line.id),
        ),
        true,
      );
    },
  );
  test('lector rechaza corrupción, extras y sustitución de manifest', () async {
    final s = await capture();
    addTearDown(s.close);
    final out = await RecoveryPackageService().generate(
      s,
      privateDirectory: Directory('${dir.path}/reader'),
      cancellation: RecoveryCancellation(),
    );
    final reader = RecoveryPackageReader();
    final digest = await reader.verify(out, RecoveryCancellation());
    await expectLater(
      reader.verify(out, RecoveryCancellation(), expectedDigest: '0' * 64),
      throwsFormatException,
    );
    final manifest = await reader.manifest(out);
    final chunk = File(
      '${out.path}/${((manifest['chunks'] as List).first as Map)['file']}',
    );
    final bytes = await chunk.readAsBytes();
    await chunk.writeAsString('corrupto');
    await expectLater(
      reader.verify(out, RecoveryCancellation()),
      throwsFormatException,
    );
    await chunk.writeAsBytes(bytes);
    await File('${out.path}/extra').writeAsString('extra');
    await expectLater(
      reader.verify(out, RecoveryCancellation()),
      throwsFormatException,
    );
    await File('${out.path}/extra').delete();
    expect(
      await reader.verify(out, RecoveryCancellation(), expectedDigest: digest),
      digest,
    );
  });
  test(
    '20 mil eventos y proyecciones: lotes acotados, tiempos y RSS observada',
    () async {
      const volume = 20000;
      for (var base = 0; base < volume; base += 500) {
        await h.db.batch((batch) {
          for (var i = base; i < base + 500; i++) {
            final tail = (i + 1).toString().padLeft(12, '0');
            final id = '10000000-0000-4000-8000-$tail';
            final event = '20000000-0000-4000-8000-$tail';
            batch.customStatement(
              "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,server_sequence,created_at_local,created_at_server,payload,delivery_status) VALUES (?,'supplier',?,'proveedor_creado','volume','fixture',?,1794153600,1794153600,?,'delivered')",
              [
                event,
                id,
                i + 1000,
                jsonEncode({
                  'name': 'Proveedor $i',
                  'phone': null,
                  'notes': null,
                }),
              ],
            );
            batch.customStatement(
              'INSERT INTO suppliers(id,name,created_event_id,last_event_id,last_server_sequence) VALUES (?,?,?,?,?)',
              [id, 'Proveedor $i', event, event, i + 1000],
            );
          }
        });
      }
      final rssStart = ProcessInfo.currentRss;
      var peak = rssStart;
      final monitor = Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
      });
      final timer = Stopwatch()..start();
      final s = await capture();
      final captureMs = timer.elapsedMilliseconds;
      addTearDown(s.close);
      final out = await RecoveryPackageService().generate(
        s,
        privateDirectory: Directory('${dir.path}/volume'),
        cancellation: RecoveryCancellation(),
      );
      final totalMs = timer.elapsedMilliseconds;
      monitor.cancel();
      final m = await RecoveryPackageReader().manifest(out);
      final chunks = m['chunks'] as List;
      expect(
        chunks.every(
          (c) => (c['rows'] as int) <= 1000 && (c['bytes'] as int) <= 4194304,
        ),
        true,
      );
      expect(
        chunks
            .where((c) => c['entity'] == 'events')
            .fold<int>(0, (n, c) => n + c['rows'] as int),
        volume + 1,
      );
      final report = {
        'rows_per_main_entity': volume + 1,
        'snapshot_bytes': await s.file.length(),
        'package_bytes': chunks.fold<int>(0, (n, c) => n + c['bytes'] as int),
        'chunks': chunks.length,
        'capture_ms': captureMs,
        'total_ms': totalMs,
        'rss_start': rssStart,
        'rss_peak_sampled': peak,
        'rss_delta_sampled': peak - rssStart,
        'rss_scope':
            'Flutter test process incl. VM and fixture, 10ms sampling; not a heap ceiling',
      };
      final path = Platform.environment['POS_RECOVERY_METRICS'];
      if (path != null) await File(path).writeAsString(jsonEncode(report));
      expect(await source.hasChangesSince(s), false);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'rechazo histórico sin efecto es aviso; sin secuencia solo queda evidencia original',
    () async {
      const id = '30000000-0000-4000-8000-000000000001';
      await h.db.customStatement(
        "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,created_at_local,payload,delivery_status,rejection_reason) VALUES (?,'supplier',?,'proveedor_creado','fixture','fixture',1794153600,?,'rejected','rechazo histórico')",
        [
          id,
          id,
          jsonEncode({
            'name': 'No llegó a proyección',
            'phone': null,
            'notes': null,
          }),
        ],
      );
      const partial = '30000000-0000-4000-8000-000000000002';
      await h.db.customStatement(
        "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,server_sequence,created_at_local,payload,delivery_status) VALUES (?,'supplier',?,'proveedor_creado','fixture','fixture',8,1794153600,?,'rejected')",
        [
          partial,
          partial,
          jsonEncode({
            'name': 'Fecha remota desconocida',
            'phone': null,
            'notes': null,
          }),
        ],
      );
      final s = await capture();
      addTearDown(s.close);
      final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
      expect(d.admissible, true);
      final partialEvidence =
          s
                  .exportRows('event_provenance')
                  .singleWhere(
                    (e) => e['event_id'] == partial,
                  )['non_official_evidence']
              as Map;
      expect(
        (partialEvidence['payload'] as Map)['name'],
        'Fecha remota desconocida',
      );
      expect(
        s.exportRows('events').where((e) => e['event_id'] == partial),
        isEmpty,
      );
      expect(d.warnings, contains('historical_rejections_preserved'));
      expect(s.exportRows('events').where((e) => e['event_id'] == id), isEmpty);
      expect(
        s
            .exportRows('event_provenance')
            .singleWhere((e) => e['event_id'] == id)['non_official_evidence'],
        isA<Map>(),
      );
    },
  );
  test('intención sin evento, reserva masiva y secretos extra bloquean', () async {
    await h.db.customStatement(
      "INSERT INTO sale_adjustment_intents(operation_id,event_id,event_json) VALUES ('reserved','no-event','{}')",
    );
    await h.db.customStatement(
      "INSERT INTO bulk_edit_operations(operation_id,batch_id,product_id,mode,intent_json,local_state,confirmed_at) VALUES ('op','batch','product','server_sync','{}','confirmada',1)",
    );
    final event = (await h.db.select(h.db.events).get()).single;
    final payload = Map<String, Object?>.from(jsonDecode(event.payload) as Map)
      ..['token'] = 'DO_NOT_EXPORT';
    await h.db.customStatement('UPDATE events SET payload=?', [
      jsonEncode(payload),
    ]);
    final s = await capture();
    addTearDown(s.close);
    final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
    expect(
      d.blockers.map((e) => e['code']),
      containsAll([
        'missing_event',
        'unapplied_intention',
        'incompatible_event_contract',
      ]),
    );
    expect(await s.file.exists(), true);
  });
  test('fila enorme se diagnostica antes de traerla a Dart', () async {
    await h.db.customStatement('UPDATE suppliers SET notes=?', ['x' * 4194305]);
    final s = await capture();
    addTearDown(s.close);
    final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
    expect(d.admissible, false);
    expect(d.blockers.map((e) => e['code']), contains('row_exceeds_4mib'));
  });

  test(
    'writer SQLite en otro isolate durante VACUUM: corte WAL de un solo commit',
    () async {
      final port = ReceivePort();
      final started = Completer<void>();
      final done = Completer<void>();
      final subscription = port.listen((message) {
        if (message == 'started') {
          started.complete();
        } else if (message == 'done') {
          done.complete();
        } else {
          if (!done.isCompleted) done.completeError(StateError('$message'));
        }
      });
      final worker = await Isolate.spawn(_walWriter, <Object?>[
        '${dir.path}/origin.sqlite',
        port.sendPort,
      ]);
      try {
        await started.future;
        final s = await capture();
        addTearDown(s.close);
        final row = s.rows('suppliers').single;
        expect(row['name'], row['notes']);
        expect(
          s.rows('sync_checkpoints').single['last_full_pull_server_sequence'],
          int.parse(row['name'] as String) + 200,
        );
        await done.future;
        expect(await source.hasChangesSince(s), true);
      } finally {
        worker.kill(priority: Isolate.immediate);
        await subscription.cancel();
        port.close();
      }
    },
  );

  test(
    'identidad conocida no se inventa y cambio de dataset se detecta',
    () async {
      const instance = '40000000-0000-4000-8000-000000000001';
      const generation = '40000000-0000-4000-8000-000000000002';
      await h.db.customStatement(
        'UPDATE recovery_local_state SET server_instance_id=?,generation_id=?,dataset_id=?',
        [instance, generation, 'dataset'],
      );
      final s = await capture();
      addTearDown(s.close);
      expect((s.cut['source'] as Map)['identity_provenance'], 'known');
      expect((s.cut['source'] as Map)['generation_id'], generation);
      expect(await source.hasChangesSince(s), false);
      await h.db.customStatement(
        "UPDATE recovery_local_state SET dataset_id='otro'",
      );
      expect(await source.hasChangesSince(s), true);
    },
  );

  test(
    'contador igual tras restauración/reuso no oculta contenido distinto',
    () async {
      final s = await capture();
      addTearDown(s.close);
      expect(await source.hasChangesSince(s), false);
      await h.db.customStatement(
        "UPDATE suppliers SET name='Contenido distinto'",
      );
      await h.db.customStatement(
        'UPDATE recovery_local_state SET data_revision=?',
        [int.parse(s.cut['data_revision'] as String)],
      );
      expect(await source.hasChangesSince(s), true);
    },
  );

  test(
    'secuencia oficial duplicada y fecha incompatible se diagnostican',
    () async {
      const id = '50000000-0000-4000-8000-000000000001';
      await h.db.customStatement(
        "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,server_sequence,created_at_local,created_at_server,payload,delivery_status) VALUES (?,'supplier',?,'proveedor_creado','fixture','fixture',7,1794153600,1794153600,?,'delivered')",
        [
          id,
          id,
          jsonEncode({'name': 'Otro', 'phone': null, 'notes': null}),
        ],
      );
      await h.db.customStatement(
        'UPDATE sync_checkpoints SET last_full_pull_at=1.5',
      );
      final s = await capture();
      addTearDown(s.close);
      final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
      expect(
        d.blockers.map((e) => e['code']),
        containsAll(['duplicate_official_sequence', 'incompatible_checkpoint']),
      );
    },
  );

  test(
    'identidad de paquete alterada no puede derivar rutas externas',
    () async {
      final s = await capture();
      final file = s.file;
      s.close();
      final cutFile = File('${file.parent.path}/cut.json');
      final cut = Map<String, Object?>.from(
        jsonDecode(await cutFile.readAsString()) as Map,
      );
      cut['package_id'] = '../outside';
      await cutFile.writeAsString(recoveryCanonical(cut));
      final altered = await SqliteRecoverySnapshot.open(file);
      addTearDown(altered.close);
      await expectLater(
        RecoveryPackageService().generate(
          altered,
          privateDirectory: Directory('${dir.path}/secure'),
          cancellation: RecoveryCancellation(),
        ),
        throwsFormatException,
      );
      expect(Directory('${dir.path}/outside').existsSync(), false);
    },
  );

  test(
    'mapeo preserva totales exactos de caja mayores que entero JSON seguro y rechaza identificación vacía',
    () async {
      const cash = '60000000-0000-4000-8000-000000000001';
      const espacio = '60000000-0000-4000-8000-000000000002';
      const total = '9007199254740992';
      await h.db.customStatement(
        "INSERT INTO cash_sessions(id,device_id,opened_by_user_id,closed_by_user_id,status,opened_at_ms,closed_at_ms,opening_minor,counted_minor,income_minor,expense_minor,expected_minor,difference_minor,close_snapshot) VALUES (?,'fixture','u','u','closed',1,2,0,0,?,?,'0','0','{}')",
        [cash, total, total],
      );
      await h.db.customStatement(
        "INSERT INTO espacios(id,nombre,identificacion,visibilidad) VALUES (?,'Vacío','',0)",
        [espacio],
      );
      final s = await capture();
      addTearDown(s.close);
      final mapper = RecoveryRowMapper(s);
      final row = mapper.map('cash_sessions', s.rows('cash_sessions').single)!;
      expect(row['income_minor'], total);
      expect(row['expense_minor'], total);
      expect(row['expected_minor'], '0');
      expect(
        () => mapper.map('espacios', s.rows('espacios').single),
        throwsStateError,
      );
    },
  );

  test(
    'refs locales repetidas de un mismo evento se exportan como conjunto sin modificar origen',
    () async {
      await h.db.customStatement(
        'INSERT INTO event_refs(event_ref_id,event_id,ref_type,ref_id,relationship,server_sequence,source) SELECT ?,event_id,ref_type,ref_id,relationship,server_sequence,source FROM event_refs LIMIT 1',
        [const Uuid().v4()],
      );
      final before = await contents();
      final s = await capture();
      addTearDown(s.close);
      expect(s.count('event_refs'), 2);
      expect(s.exportRows('event_refs').length, 1);
      final out = await RecoveryPackageService().generate(
        s,
        privateDirectory: Directory('${dir.path}/refs'),
        cancellation: RecoveryCancellation(),
      );
      await RecoveryPackageReader().verify(out, RecoveryCancellation());
      expect(await contents(), before);
    },
  );

  test(
    'sin checkpoint conocido conserva null como advertencia, sin fecha inventada ni red',
    () async {
      await h.db.customStatement('DELETE FROM sync_checkpoints');
      final s = await capture();
      addTearDown(s.close);
      final d = await RecoveryDiagnostic.inspect(s, RecoveryCancellation());
      expect(d.admissible, true);
      expect(d.warnings, contains('no_full_pull_known'));
      expect(d.checkpoint, {
        'last_full_pull_sequence': null,
        'last_full_pull_at': null,
      });
      final out = await RecoveryPackageService().generate(
        s,
        privateDirectory: Directory('${dir.path}/unknown-pull'),
        cancellation: RecoveryCancellation(),
      );
      final manifest = await RecoveryPackageReader().manifest(out);
      expect(manifest['checkpoint'], d.checkpoint);
      expect(manifest['baseline_high_watermark'], '7');
      expect(network.attempts, 0);
    },
  );
  test('serialización rechaza flotantes, conserva null y payload entero', () {
    expect(
      recoveryCanonical({
        'z': [1, null],
        'a': 'ñ',
      }),
      '{"a":"ñ","z":[1,null]}',
    );
    expect(recoveryCanonical({'x': 1.0}), '{"x":1}');
    expect(() => recoveryCanonical(-0.0), throwsFormatException);
    expect(
      () => recoveryCanonical(-9223372036854775808),
      throwsFormatException,
    );
    expect(
      () => recoveryUtcFromSeconds(-9223372036854775808),
      throwsFormatException,
    );
    expect(recoveryUtcFromSeconds(0), '1970-01-01T00:00:00.000Z');
    expect(() => recoveryCanonical({'x': 1.5}), throwsFormatException);
    expect(() => recoveryCanonical(9007199254740992), throwsFormatException);
  });
}
