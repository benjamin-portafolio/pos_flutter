/// Identidad del destino, independiente del nombre y del orden del listado.
class ClaveVariante {
  const ClaveVariante(this.productId, this.variantId);

  final String productId;
  final String variantId;

  @override
  bool operator ==(Object other) =>
      other is ClaveVariante &&
      productId == other.productId &&
      variantId == other.variantId;

  @override
  int get hashCode => Object.hash(productId, variantId);
}
