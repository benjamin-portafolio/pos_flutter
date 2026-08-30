enum InventoryResourceFilter {
  all('Todos'),
  products('Productos'),
  independent('Independientes'),
  ingredients('Ingredientes', available: false),
  withStock('Con existencia'),
  withoutStock('Sin existencia');

  const InventoryResourceFilter(this.label, {this.available = true});

  final String label;
  final bool available;
}
