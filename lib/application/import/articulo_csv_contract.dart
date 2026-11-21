/// Contratos explícitos. El formato de diez columnas solo representa altas.
abstract final class ArticuloCsvContract {
  /// Formato público simplificado. La firma exacta del encabezado identifica
  /// el formato; no necesita una columna de versión por fila.
  static const columnasSimplificadas = <String>[
    'product_id',
    'variant_id',
    'categoria',
    'nombre_articulo',
    'tipo_venta',
    'unidad_venta',
    'nombre_variante',
    'precio_venta',
    'precio_oferta',
    'precio_coste',
    'seguimiento_existencias',
    'existencias',
    'existencias_objetivo',
    'codigo_barras',
    'proveedor_actual',
    'eliminar_variante',
  ];
  static const versionReposicion = '2';
  static const columnasReposicion = <String>[
    ...columnasConVariantes,
    'version_csv',
    'current_supplier_id',
    'accion_proveedor_actual',
    'target_stock_atomic',
    'unidad_objetivo_id',
    'accion_objetivo',
  ];
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
  static const columnasConIdsAnteriores = <String>[
    'product_id',
    'variant_id',
    ...columnasAnteriores,
  ];
  static const columnasConOfertaAnteriores = <String>[
    ...columnasConIdsAnteriores,
    'precio_oferta',
    'accion_oferta',
  ];
  static const columnasConVariantes = <String>[
    ...columnas,
    'eliminar_variante',
    'recurso_inventario_id',
  ];
  static const columnas = <String>[
    ...columnasConIdsAnteriores,
    'precio_oferta',
    'eliminar_producto',
  ];
}
