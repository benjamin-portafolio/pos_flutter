import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../../domain/clientes/cliente_resumen.dart';

/// Pestañas del listado de Gestión de clientes.
enum ClienteResumenTab { todos, conAdeudo }

/// Búsqueda, filtrado y ordenamiento del listado de clientes.
///
/// Lógica pura de presentación: la búsqueda por nombre acepta coincidencias
/// parciales e ignora mayúsculas y acentos; cada pestaña se combina con la
/// búsqueda activa.
class ClienteResumenQuery {
  /// Normaliza para comparar: minúsculas, sin acentos y sin espacios sobrantes.
  static String normalize(String value) => unorm
      .nfkd(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .trim();

  /// Aplica la pestaña y la búsqueda a la lista completa de resúmenes.
  ///
  /// - [ClienteResumenTab.todos]: alfabético por nombre.
  /// - [ClienteResumenTab.conAdeudo]: solo saldo negativo, del mayor al menor
  ///   importe adeudado.
  static List<ClienteResumen> apply(
    List<ClienteResumen> clientes, {
    required ClienteResumenTab tab,
    required String search,
  }) {
    final query = normalize(search);
    final filtered = clientes
        .where((c) => query.isEmpty || normalize(c.nombre).contains(query))
        .toList();
    if (tab == ClienteResumenTab.todos) {
      filtered.sort(_porNombre);
      return filtered;
    }
    final deudores = filtered.where((c) => c.saldoMinor.isNegative).toList()
      ..sort(_porAdeudo);
    return deudores;
  }

  static int _porNombre(ClienteResumen a, ClienteResumen b) {
    final byName = normalize(a.nombre).compareTo(normalize(b.nombre));
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }

  /// Mayor adeudo primero: los saldos más negativos van al inicio.
  static int _porAdeudo(ClienteResumen a, ClienteResumen b) {
    final bySaldo = a.saldoMinor.compareTo(b.saldoMinor);
    return bySaldo != 0 ? bySaldo : _porNombre(a, b);
  }
}