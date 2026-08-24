enum InventoryResourceFilter {
  all('Todos'),
  inactive('Inactivos');

  const InventoryResourceFilter(this.label);

  final String label;
}
