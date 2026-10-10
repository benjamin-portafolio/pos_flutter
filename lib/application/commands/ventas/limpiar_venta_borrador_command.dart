class LimpiarVentaBorradorCommand {
  const LimpiarVentaBorradorCommand({
    required this.saleId,
    this.expectedDraftEventId,
  });

  final String saleId;

  /// Si se indica, sólo permite limpiar la revisión que emitió el documento.
  final String? expectedDraftEventId;
}
