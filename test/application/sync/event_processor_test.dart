import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/event_handler.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';

void main() {
  test('apply despacha el evento al handler registrado', () async {
    SyncEvent? appliedEvent;
    final event = _event('espacio_creado');
    final processor = EventProcessor(
      handlers: {
        'espacio_creado': (event) async {
          appliedEvent = event;
        },
      },
    );

    await processor.apply(event);

    expect(appliedEvent, same(event));
  });

  test('apply rechaza eventos sin handler registrado', () async {
    final processor = EventProcessor(handlers: const {});

    expect(
      () => processor.apply(_event('evento_desconocido')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('copia el registro de handlers al construirlo', () async {
    var wasApplied = false;
    final handlers = <String, EventHandler>{
      'espacio_creado': (event) async {
        wasApplied = true;
      },
    };
    final processor = EventProcessor(handlers: handlers);

    handlers.clear();

    await processor.apply(_event('espacio_creado'));

    expect(wasApplied, isTrue);
  });
}

SyncEvent _event(String eventType) {
  return SyncEvent(
    eventId: 'event_1',
    aggregateType: 'espacio',
    aggregateId: 'espacio_1',
    eventType: eventType,
    deviceId: 'test_device',
    userId: 'test_user',
    createdAtLocal: DateTime(2026),
    payload: const {},
  );
}
