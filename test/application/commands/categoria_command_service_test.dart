import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/categoria_command_service.dart';
import 'package:pos_flutter/application/commands/crear_categoria_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late CategoriaCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    service = CategoriaCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
    );
  });

  test(
    'crearCategoria normaliza y crea el evento con una referencia',
    () async {
      await service.crearCategoria(
        const CrearCategoriaCommand(
          nombre: ' Bebidas ',
          color: ColorCategoria.cyan,
        ),
      );

      final event = eventStore.event!;
      expect(event.aggregateType, 'category');
      expect(event.eventType, 'categoria_creada');
      expect(event.baseVersion, 1);
      expect(event.payload, {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': null,
      });
      expect(eventStore.refs, hasLength(1));
      expect(eventStore.refs.single.refType, 'category');
      expect(eventStore.refs.single.refId, event.aggregateId);
      expect(eventStore.refs.single.relationship, 'affects');
    },
  );

  test('crearCategoria permite neutral cuando no se eligió color', () async {
    await service.crearCategoria(
      const CrearCategoriaCommand(
        nombre: 'Sin color',
        color: ColorCategoria.neutral,
      ),
    );

    expect(eventStore.event!.payload['color_key'], 'neutral');
  });

  test('crearCategoria rechaza nombres vacíos antes de guardar', () async {
    await expectLater(
      service.crearCategoria(
        const CrearCategoriaCommand(nombre: '  ', color: ColorCategoria.amber),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(eventStore.event, isNull);
  });
}

class _CapturingLocalEventStore implements LocalEventStore {
  SyncEvent? event;
  List<LocalEventRef> refs = const [];

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    this.event = event;
    this.refs = refs;
  }
}
