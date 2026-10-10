/// Resultado de una intención completa, independiente del dispositivo lector.
enum SaleBarcodeReadOutcome {
  added,
  notFound,
  selectionCancelled,
  quantityCancelled,
  unitUnavailable,
  interrupted,
}
