import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/clientes/cliente_resumen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/models/cliente_resumen_query.dart';

ClienteResumen _cliente(String id, String nombre, {BigInt? saldo}) =>
    ClienteResumen(
      id: id,
      nombre: nombre,
      telefono: null,
      active: true,
      compras: 0,
      ultimoMovimiento: null,
      saldoMinor: saldo ?? BigInt.zero,
    );

List<ClienteResumen> _clientes() => [
  _cliente('a', 'Ana López'),
  _cliente('b', 'José Álvarez'),
  _cliente('c', 'María Hernández'),
];

void main() {
  group('ClienteResumenQuery.normalize', () {
    test('ignora mayúsculas, acentos y espacios sobrantes', () {
      expect(ClienteResumenQuery.normalize('  José Álvarez  '), 'jose alvarez');
      expect(ClienteResumenQuery.normalize('Ñandú'), 'nandu');
      expect(ClienteResumenQuery.normalize('MARÍA'), 'maria');
    });
  });

  group('ClienteResumenQuery.apply · Todos los clientes', () {
    test('ordena alfabéticamente por nombre', () {
      final result = ClienteResumenQuery.apply(
        _clientes(),
        tab: ClienteResumenTab.todos,
        search: '',
      );
      expect(
        result.map((c) => c.nombre).toList(),
        ['Ana López', 'José Álvarez', 'María Hernández'],
      );
    });

    test('ordena ignorando acentos', () {
      final result = ClienteResumenQuery.apply(
        [_cliente('x', 'Álvaro Benítez'), _cliente('y', 'Alberto Díaz')],
        tab: ClienteResumenTab.todos,
        search: '',
      );
      expect(
        result.map((c) => c.nombre).toList(),
        ['Alberto Díaz', 'Álvaro Benítez'],
      );
    });

    test('busca coincidencias parciales ignorando mayúsculas y acentos', () {
      final result = ClienteResumenQuery.apply(
        _clientes(),
        tab: ClienteResumenTab.todos,
        search: 'JOSE',
      );
      expect(result.map((c) => c.id).toList(), ['b']);

      final parcial = ClienteResumenQuery.apply(
        _clientes(),
        tab: ClienteResumenTab.todos,
        search: 'alv',
      );
      expect(parcial.map((c) => c.id).toList(), ['b']);
    });

    test('sin coincidencias devuelve lista vacía', () {
      final result = ClienteResumenQuery.apply(
        _clientes(),
        tab: ClienteResumenTab.todos,
        search: 'noexiste',
      );
      expect(result, isEmpty);
    });
  });

  group('ClienteResumenQuery.apply · Clientes con adeudo', () {
    test('solo saldos negativos ordenados del mayor al menor adeudo', () {
      final clientes = [
        _cliente('a', 'Ana', saldo: -BigInt.from(500)),
        _cliente('b', 'Benito', saldo: -BigInt.from(50)),
        _cliente('c', 'Carlos', saldo: -BigInt.from(5000)),
        _cliente('d', 'Diana', saldo: BigInt.zero),
        _cliente('e', 'Ernesto', saldo: BigInt.from(200)),
      ];
      final result = ClienteResumenQuery.apply(
        clientes,
        tab: ClienteResumenTab.conAdeudo,
        search: '',
      );
      expect(result.map((c) => c.id).toList(), ['c', 'a', 'b']);
    });

    test('empata adeudos iguales por nombre', () {
      final clientes = [
        _cliente('a', 'Ana', saldo: -BigInt.from(100)),
        _cliente('b', 'Benito', saldo: -BigInt.from(100)),
      ];
      final result = ClienteResumenQuery.apply(
        clientes,
        tab: ClienteResumenTab.conAdeudo,
        search: '',
      );
      expect(result.map((c) => c.id).toList(), ['a', 'b']);
    });

    test('se combina con la búsqueda', () {
      final clientes = [
        _cliente('a', 'Ana', saldo: -BigInt.from(500)),
        _cliente('b', 'Benito', saldo: -BigInt.from(50)),
        _cliente('c', 'Araceli', saldo: -BigInt.from(200)),
      ];
      final result = ClienteResumenQuery.apply(
        clientes,
        tab: ClienteResumenTab.conAdeudo,
        search: 'ara',
      );
      // 'Araceli' coincide con el texto y con la pestaña de adeudos; los demás
      // quedan fuera por no coincidir con el texto o por no tener adeudo.
      expect(result.map((c) => c.id).toList(), ['c']);
    });
  });
}