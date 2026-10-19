import 'dart:async';

import 'package:pos_flutter/domain/articulos/articulo_listado.dart';

import 'fake_producto_repository.dart';

/// Repite el catálogo actual al suscribirse, como la consulta local de artículos.
class FakeReportsProductoRepository extends FakeProductoRepository {
  FakeReportsProductoRepository({this.emitInitial = true});

  final bool emitInitial;
  List<ArticuloListado> articles = [];
  final controller = StreamController<List<ArticuloListado>>.broadcast();
  int watchCalls = 0;

  void emit(List<ArticuloListado> value) {
    articles = value;
    controller.add(value);
  }

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    watchCalls++;
    return Stream.multi((sink) {
      final subscription = controller.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      if (emitInitial) sink.add(articles);
      sink.onCancel = subscription.cancel;
    });
  }
}
