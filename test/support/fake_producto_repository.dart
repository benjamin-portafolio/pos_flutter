import 'package:pos_flutter/domain/repositories/producto_repository.dart';

/// Dependencia de catálogo para pruebas de Caja sin lecturas ni búsquedas.
/// Cualquier consulta inesperada falla, en vez de simular un agregado.
class FakeProductoRepository implements ProductoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
