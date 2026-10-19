import 'dart:convert';

import '../commands/inventario/registrar_entrada_confirmada_result.dart';

/// Commit local. La entrega/aceptación remota se consulta por los IDs originales.
class ResultadoOperacionMasiva {
  ResultadoOperacionMasiva({
    required this.operationId,
    required this.productId,
    required this.catalogEventId,
    required Iterable<RegistrarEntradaConfirmadaResult> entradas,
  }) : entradas = List.unmodifiable(entradas);

  final String operationId;
  final String productId;
  final String? catalogEventId;
  final List<RegistrarEntradaConfirmadaResult> entradas;
  List<String> get eventIds => [
    ?catalogEventId,
    for (final entrada in entradas) entrada.eventId,
  ];

  String get json => jsonEncode({
    'operation_id': operationId,
    'product_id': productId,
    'catalog_event_id': catalogEventId,
    'receipts': entradas.map((e) => e.toJson()).toList(),
  });

  factory ResultadoOperacionMasiva.fromJson(String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    return ResultadoOperacionMasiva(
      operationId: j['operation_id'] as String,
      productId: j['product_id'] as String,
      catalogEventId: j['catalog_event_id'] as String?,
      entradas: (j['receipts'] as List).map(
        (e) => RegistrarEntradaConfirmadaResult.fromJson(
          Map<String, Object?>.from(e as Map),
        ),
      ),
    );
  }
}
