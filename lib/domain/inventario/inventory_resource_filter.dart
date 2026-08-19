enum InventoryResourceFilter {
  all('Todos'),
  withoutSaleLink('Sin vínculo de venta'),
  linkedToVariant('Vinculados a variante'),
  usedInRecipes('Usados en recetas'),
  inactive('Inactivos');

  const InventoryResourceFilter(this.label);

  final String label;
}
