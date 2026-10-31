/// Regla única para nuevas capturas y recálculo de snapshots acreditados.
class EffectiveSalePrice {
  static ({int amount, String source}) resolve({
    required String mode,
    required int normal,
    required int? offer,
  }) {
    if (!['normal', 'offer'].contains(mode) ||
        normal <= 0 ||
        normal > 9007199254740991 ||
        (offer != null && (offer <= 0 || offer > normal))) {
      throw const FormatException('Alternativas de precio inválidas.');
    }
    return mode == 'offer' && offer != null
        ? (amount: offer, source: 'offer')
        : (amount: normal, source: 'normal');
  }
}
