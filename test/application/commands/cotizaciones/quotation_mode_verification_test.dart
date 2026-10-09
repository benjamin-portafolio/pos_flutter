import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_guardada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';

import '../../../support/quotation_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    test(
      'P23/P24: refs declaradas y validadas antes de persistencia $mode',
      () async {
        final h = QuotationHarness(mode: mode);
        try {
          await h.seed();
          await h.add();
          await h.add(QuotationHarness.recipeId);
          await h.add(QuotationHarness.measuredId);
          final recorder = _RecordingEventStore(h.events);
          final service = CotizacionCommandService(
            store: h.db.quotationDao,
            drafts: h.db.saleDao,
            events: recorder,
            context: h.context,
            validator: h.validator,
          );
          final save = await h.intent();
          await service.guardar(save);
          final saved = recorder.entries.single;
          expect(saved.refs, hasLength(5));
          final before = await h.contents();
          expect(
            () => CotizacionGuardadaPayload.fromJson(
              saved.event.payload,
            ).refs(''),
            throwsFormatException,
          );
          expect(await h.contents(), before);
          await h.drafts.limpiar(
            LimpiarVentaBorradorCommand(saleId: save.saleId),
          );
          final recovery = RecuperarCotizacionCommand(
            quotationId: save.quotationId,
            expectedQuotationEventId: save.eventId,
          );
          await service.recuperar(recovery);
          expect(recorder.entries, hasLength(5));
          expect(recorder.entries.skip(1).map((e) => e.refs.length), [
            4,
            4,
            5,
            5,
          ]);
          final linked = recorder.entries.last;
          final after = await h.contents();
          expect(
            () => CotizacionRecuperadaPayload.fromJson(
              linked.event.payload,
            ).refs(recovery.saleId),
            throwsFormatException,
          );
          expect(await h.contents(), after);
          for (final entry in recorder.entries) {
            expect(entry.event.deliveryStatus, 'not_required');
            expect(
              entry.refs.every(
                (r) =>
                    r.refId.trim().isNotEmpty &&
                    r.refType.trim().isNotEmpty &&
                    ['affects', 'uses'].contains(r.relationship),
              ),
              isTrue,
            );
            final persisted = await (h.db.select(
              h.db.eventRefs,
            )..where((t) => t.eventId.equals(entry.event.eventId))).get();
            expect(
              persisted.length,
              mode == AppMode.serverSync ? entry.refs.length : 0,
            );
            if (mode == AppMode.serverSync) {
              expect(
                persisted.map(
                  (r) => '${r.refType}:${r.refId}:${r.relationship}',
                ),
                entry.refs.map(
                  (r) => '${r.refType}:${r.refId}:${r.relationship}',
                ),
              );
            }
          }
          expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
          final output = Platform.environment['POS_QUOTATION_VERIFICATION_DIR'];
          if (output != null) {
            await Directory(output).create(recursive: true);
            await File('$output/refs-${mode.name}.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'mode': mode.name,
                'invalid_refs_rejected': true,
                'persist_refs': mode == AppMode.serverSync,
                'events': [
                  for (final e in recorder.entries)
                    {
                      'event_id': e.event.eventId,
                      'aggregate_type': e.event.aggregateType,
                      'delivery_status': e.event.deliveryStatus,
                      'declared_refs': [
                        for (final r in e.refs)
                          {
                            'ref_type': r.refType,
                            'ref_id': r.refId,
                            'relationship': r.relationship,
                          },
                      ],
                    },
                ],
              }),
            );
          }
        } finally {
          await h.dispose();
        }
      },
    );
  }
}

class _RecordingEventStore implements LocalEventStore {
  _RecordingEventStore(this.delegate);
  final LocalEventStore delegate;
  final entries = <LocalEventAppend>[];
  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    entries.add(LocalEventAppend(event: event, refs: List.unmodifiable(refs)));
    await delegate.appendAndApply(event, refs: refs);
  }
}
