/// La asignación terminó, pero no se pudo confirmar el paso posterior de venta.
class SaleBarcodeAssignedException implements Exception {
  const SaleBarcodeAssignedException(this.cause);

  final Object cause;

  static const message =
      'El código quedó guardado. No se pudo confirmar el agregado a la venta. '
      'Revisa la venta antes de volver a escanear; '
      'esta lectura no se reintentará automáticamente.';

  @override
  String toString() => message;
}
