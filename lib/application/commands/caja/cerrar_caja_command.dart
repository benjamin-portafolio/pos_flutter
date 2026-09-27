class CerrarCajaCommand {
  const CerrarCajaCommand({
    required this.sessionId,
    required this.countedMinor,
    this.notes,
  });
  final String sessionId;
  final int countedMinor;
  final String? notes;
}
