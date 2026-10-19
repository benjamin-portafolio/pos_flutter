/// Resultado tipado de la edición comercial por producto.
///
/// `eventId` nulo es una omisión real: estado final idéntico sin evento,
/// referencias, versiones ni respaldos nuevos. La sesión 3 registra el ID
/// emitido dentro de su propia transacción, sin buscarlo por «último».
class EditarArticuloComercialResult {
  const EditarArticuloComercialResult._({
    required this.productId,
    required this.eventId,
  });

  const EditarArticuloComercialResult.emitido({
    required String productId,
    required String eventId,
  }) : this._(productId: productId, eventId: eventId);

  const EditarArticuloComercialResult.omitido({required String productId})
    : this._(productId: productId, eventId: null);

  final String productId;
  final String? eventId;

  bool get emitido => eventId != null;
}
