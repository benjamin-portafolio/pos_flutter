/// Base observada, sin sustituirla por la base viva al preparar una revisión.
class BaseRevisionMasiva {
  const BaseRevisionMasiva({
    required this.id,
    required this.version,
    required this.eventId,
    required this.serverSequence,
  });

  final String id;
  final int version;
  final String? eventId;
  final int? serverSequence;

  /// Un eco puede acreditar secuencia sin modificar el estado observado.
  bool mismoEstado(BaseRevisionMasiva other) =>
      id == other.id && version == other.version && eventId == other.eventId;
}
