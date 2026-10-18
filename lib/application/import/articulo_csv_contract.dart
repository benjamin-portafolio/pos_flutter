/// Contratos explícitos. El formato anterior solo representa altas.
abstract final class ArticuloCsvContract {
  static const separador = ',';
  static const bom = '\uFEFF';
  static const columnasAnteriores = <String>[
    'categoria',
    'nombre_articulo',
    'tipo_venta',
    'unidad_venta',
    'nombre_variante',
    'precio_venta',
    'precio_coste',
    'seguimiento_existencias',
    'existencias',
    'codigo_barras',
  ];
  static const columnas = <String>[
    'product_id',
    'variant_id',
    ...columnasAnteriores,
  ];
}
