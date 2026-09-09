import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';

void main() {
  const baseId = '00000000-0000-4000-8000-000000000001';
  final before = ProductoCreadoPayload.simple(
    nombre: 'Café',
    categoriaId: null,
    varianteId: '00000000-0000-4000-8000-000000000002',
    precioVentaMenor: 1000,
  );
  test('borrado explícito conserva estado y base en la serialización', () {
    final payload = ProductoActualizadoPayload(
      baseEventId: baseId,
      before: before,
      after: before,
      deleteProduct: true,
    );
    final parsed = ProductoActualizadoPayload.fromJson(payload.toJson());
    expect(parsed.deleteProduct, isTrue);
    expect(payload.toJson()['after'], isNull);
    expect(
      parsed.removedVariants.map((v) => v.id),
      before.variantes.map((v) => v.id),
    );
    expect(parsed.dependencyEventIds, {baseId});
    expect(parsed.toJson(), payload.toJson());
  });
  test('contrato previo sin delete_product conserva actualización normal', () {
    final json = ProductoActualizadoPayload(
      baseEventId: baseId,
      before: before,
      after: before,
    ).toJson();
    expect(json.containsKey('delete_product'), isFalse);
    expect(ProductoActualizadoPayload.fromJson(json).deleteProduct, isFalse);
  });
  test('rechaza bandera mal tipada, estado alterado y altas sin variantes', () {
    final json = ProductoActualizadoPayload(
      baseEventId: baseId,
      before: before,
      after: before,
      deleteProduct: true,
    ).toJson();
    expect(
      () => ProductoActualizadoPayload.fromJson({
        ...json,
        'delete_product': 'true',
      }),
      throwsFormatException,
    );
    final altered = ProductoCreadoPayload.simple(
      nombre: 'Otro',
      categoriaId: null,
      varianteId: before.variantes.single.id,
      precioVentaMenor: 1000,
    );
    expect(
      () => ProductoActualizadoPayload.fromJson({
        ...json,
        'after': altered.toJson(),
      }),
      throwsFormatException,
    );
    expect(
      () =>
          ProductoCreadoPayload.fromJson({...before.toJson(), 'variants': []}),
      throwsFormatException,
    );
  });
}
