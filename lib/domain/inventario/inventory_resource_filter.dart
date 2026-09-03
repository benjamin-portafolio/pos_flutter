enum InventoryResourceFilter {
  all('Todos'),
  products('Productos'),
  independent('Independientes'),
  ingredients('Ingredientes'),
  withStock('Con existencia'),
  withoutStock('Sin existencia');

  const InventoryResourceFilter(this.label);

  final String label;
}
