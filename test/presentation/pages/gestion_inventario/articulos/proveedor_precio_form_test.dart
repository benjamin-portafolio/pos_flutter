import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/precio_proveedor.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precio_form.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precio_input.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precios_form_result.dart';

const supplierId = '00000000-0000-4000-8000-000000000002';

void main() {
  for (final entry in {
    '0': 0,
    '0.00': 0,
    '0,00': 0,
    '12': 1200,
    '12,3': 1230,
    '12.34': 1234,
    ' 0012,34 ': 1234,
    '90071992547409.91': PrecioProveedor.maxUnidadMenor,
    '90071992547409,91': PrecioProveedor.maxUnidadMenor,
  }.entries) {
    test('precio exacto ${entry.key}', () {
      expect(ProveedorPrecioInput.parse(entry.key).unidadMenor, entry.value);
      expect(
        ProveedorPrecioInput.parse(
          ProveedorPrecioInput.format(entry.value),
        ).unidadMenor,
        entry.value,
      );
    });
  }
  for (final text in [
    '',
    ' ',
    '-1',
    '-0',
    '+1',
    '.5',
    ',5',
    '1.',
    '1,',
    '1.234',
    '1,234',
    '1,2.3',
    '1 000',
    '1e2',
    'NaN',
    '12 pesos',
    '90071992547409.92',
    '90071992547410',
    '999999999999999999999999999',
  ]) {
    test('rechaza precio "$text"', () {
      expect(() => ProveedorPrecioInput.parse(text), throwsFormatException);
    });
  }
  final original = ProveedorVariante(
    proveedorId: supplierId,
    precioInformadoMenor: 1234,
    fechaInformadaMs: 1791331200123,
  );
  test('cargar/guardar conserva precio, fecha exacta e identidad', () {
    final form = ProveedorPrecioForm.fromRelacion(original);
    expect(form.precio, '12.34');
    expect(form.conservaFecha, isTrue);
    expect(
      form.copyWith(precio: '12,34', fecha: DateTime(2027)).toRelacion(),
      same(original),
    );
  });
  test('cambiar precio utiliza fecha informada convertida a UTC', () {
    final date = DateTime(2026, 10, 8, 13, 45, 10, 123);
    final form = ProveedorPrecioForm.fromRelacion(
      original,
    ).copyWith(precio: '0', fecha: date);
    expect(form.conservaFecha, isFalse);
    expect(
      form.toRelacion().fechaInformadaMs,
      date.toUtc().millisecondsSinceEpoch,
    );
    expect(form.toRelacion().precioInformadoMenor, 0);
  });
  test('relación nueva requiere fecha válida y conserva cero explícito', () {
    expect(
      () => const ProveedorPrecioForm(
        proveedorId: supplierId,
        precio: '0',
        fecha: null,
      ).toRelacion(),
      throwsFormatException,
    );
    expect(
      () => ProveedorPrecioForm(
        proveedorId: supplierId,
        precio: '0',
        fecha: DateTime.utc(1970),
      ).toRelacion(),
      throwsFormatException,
    );
    final date = DateTime.parse('2026-10-08T13:45:10.123-06:00');
    expect(
      ProveedorPrecioForm(
        proveedorId: supplierId,
        precio: '0',
        fecha: date,
      ).toRelacion().fechaInformadaMs,
      DateTime.utc(2026, 10, 8, 19, 45, 10, 123).millisecondsSinceEpoch,
    );
  });
  test('rango de fecha mayor que DateTime se conserva sin fallar', () {
    final relation = ProveedorVariante(
      proveedorId: supplierId,
      precioInformadoMenor: 0,
      fechaInformadaMs: PrecioProveedor.maxUnidadMenor,
    );
    final form = ProveedorPrecioForm.fromRelacion(relation);
    expect(form.toRelacion(), relation);
    expect(
      ProveedorPrecioForm.formatDate(relation.fechaInformadaMs),
      contains('9007199254740991'),
    );
    expect(
      () => form.copyWith(precio: '1').toRelacion(),
      throwsFormatException,
    );
  });
  test(
    'resultado copia, ordena, impide duplicados y permite conjunto vacío',
    () {
      final input = [original];
      final result = ProveedorPreciosFormResult(input);
      input.clear();
      expect(result.proveedores, [original]);
      expect(() => result.proveedores.clear(), throwsUnsupportedError);
      expect(
        () => ProveedorPreciosFormResult([original, original]),
        throwsFormatException,
      );
      expect(ProveedorPreciosFormResult([]).proveedores, isEmpty);
    },
  );
}
