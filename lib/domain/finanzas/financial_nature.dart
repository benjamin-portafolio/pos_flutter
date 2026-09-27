/// Naturaleza/clasificación de una categoría o registro financiero adicional
/// (5 valores). Es explícita e inmutable desde el alta y nunca se infiere del
/// nombre; no representa contabilidad ni reconocimiento de utilidad.
enum FinancialNature {
  operating('operating', 'Operativo'),
  capital('capital', 'Capital'),
  assetPurchase('asset_purchase', 'Compra de equipo o activo'),
  inventoryPurchase('inventory_purchase', 'Compra de mercancía'),
  financing('financing', 'Financiamiento');

  const FinancialNature(this.code, this.label);

  /// Código persistido y usado en payloads: `operating` | `capital` |
  /// `asset_purchase` | `inventory_purchase` | `financing`.
  final String code;

  /// Etiqueta visible para la UI.
  final String label;

  /// Naturalezas que solo admiten dirección `out` (gasto), conforme al
  /// contrato §2.1: compras de equipo/activo y de mercancía.
  bool get onlyOut => this == assetPurchase || this == inventoryPurchase;

  static FinancialNature fromCode(String code) {
    return FinancialNature.values.firstWhere(
      (value) => value.code == code,
      orElse: () => throw const FormatException('nature no está permitida.'),
    );
  }
}