import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../../application/import/articulo_catalog_import_service.dart';
import '../../../../application/import/articulo_import_actualizacion.dart';
import '../../../../domain/articulos/nombre_variante.dart';

/// Revisión reutilizada en pantalla y en la confirmación con la foto más reciente.
class BulkImportReview extends StatelessWidget {
  const BulkImportReview({
    required this.reporte,
    this.soloValidas = true,
    this.onSoloValidasChanged,
    this.mostrarSeleccion = true,
    super.key,
  });

  final ArticuloImportReporte reporte;
  final bool soloValidas;
  final ValueChanged<bool>? onSoloValidasChanged;
  final bool mostrarSeleccion;

  static const instrucciones =
      'Conserva product_id y variant_id para editar. Ambos IDs vacíos significan '
      'alta. El CSV anterior de diez columnas solo permite altas.\n'
      'En actualizaciones, categoría y código de barras vacíos retiran el valor; '
      'precio de coste vacío significa costo desconocido. Nombre y precio de '
      'venta son obligatorios; nombre de variante puede quedar vacío solo si '
      'hay una variante.\n'
      'Oferta: acción/celda vacías conservan; establecer exige importe; retirar exige celda vacía. '
      'Las existencias de productos existentes son informativas: no ajustan '
      'inventario. Se conservan las variantes omitidas, recetas y proveedores.';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Revisión del archivo',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      Text(
        'Nuevos: ${reporte.productos.length} productos · ${reporte.filasNuevas} filas.\n'
        'Con cambios: ${reporte.productosConCambios.length} productos · ${reporte.filasConCambios} filas.\n'
        'Sin cambios: ${reporte.productosSinCambios.length} productos · ${reporte.filasSinCambios} filas.\n'
        'Con errores: ${reporte.productosConErrores.length} productos · ${reporte.filasExcluidas} filas excluidas.',
        key: const Key('bulk_import_valid_count'),
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
      ),
      const Text(
        'Las filas cuentan las variantes incluidas en el archivo. En altas, un '
        'producto puede tener filas válidas y excluidas.',
        style: TextStyle(fontSize: 12),
      ),
      if (reporte.erroresEstructurales)
        const Text(
          'El archivo tiene errores estructurales y no se puede importar. '
          'Revisa el encabezado y el límite de 500 filas.',
          key: Key('bulk_import_blocked'),
        ),
      if (!reporte.hayErrores &&
          reporte.productosEjecutables == 0 &&
          reporte.productosSinCambios.isNotEmpty)
        const Text(
          'Todo está sin cambios. No hay productos que guardar.',
          key: Key('bulk_import_unchanged'),
        ),
      if (reporte.productosConCambios.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Revisar diferencias actuales / propuestas'),
        for (final producto in reporte.productosConCambios)
          _Diferencias(producto: producto, categorias: reporte.categorias),
      ],
      if (reporte.hayErrores) ...[
        const SizedBox(height: 12),
        Text(
          '${reporte.errores.length} ${reporte.errores.length == 1 ? 'problema' : 'problemas'}:',
          key: const Key('bulk_import_error_count'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (mostrarSeleccion)
          SwitchListTile(
            key: const Key('import_only_valid_switch'),
            value: soloValidas,
            onChanged: reporte.erroresEstructurales
                ? null
                : onSoloValidasChanged,
            title: const Text('Importar solo las filas válidas'),
            subtitle: const Text(
              'En actualizaciones, cualquier fila inválida excluye el producto '
              'completo. En altas se conservan las filas válidas.',
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        for (final producto in reporte.productosConErrores)
          Text(
            '${producto.nombre}${producto.productId == null ? '' : ' (${producto.productId})'}: '
            'líneas excluidas ${producto.lineas.join(', ')}.',
          ),
        for (final error in reporte.errores)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${error.descripcion}: ${error.motivo}',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
      ],
    ],
  );
}

class _Diferencias extends StatelessWidget {
  const _Diferencias({required this.producto, required this.categorias});
  final ArticuloImportActualizacion producto;
  final List<ArticuloImportCategoria> categorias;

  String _categoria(String? id) => id == null
      ? 'Sin categoría'
      : categorias.where((c) => c.id == id).firstOrNull?.nombre ?? id;
  String _importe(int? minor) => minor == null
      ? 'Desconocido'
      : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  String? _texto(String? value) {
    final texto = unorm.nfkc(value ?? '').trim();
    return texto.isEmpty ? null : texto;
  }

  @override
  Widget build(BuildContext context) {
    final diferencias = <Widget>[];
    void campo(String campo, Object? actual, Object? propuesta) {
      if (actual == propuesta) return;
      diferencias.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$campo\nActual: ${actual ?? 'Vacío'}\nPropuesta: ${propuesta ?? 'Vacío'}',
          ),
        ),
      );
    }

    final actual = producto.actual;
    campo('Nombre del producto', _texto(actual.nombre), producto.nombre);
    if (actual.categoriaId != producto.categoriaId) {
      campo(
        'Categoría',
        _categoria(actual.categoriaId),
        _categoria(producto.categoriaId),
      );
    }
    final variantes = {for (final v in actual.variantes) v.id: v};
    for (final propuesta in producto.variantes) {
      final anterior = variantes[propuesta.id]!;
      final etiqueta =
          'Variante ${anterior.nombre ?? 'única'} (${anterior.id}), línea ${propuesta.linea}';
      campo(
        '$etiqueta · Nombre',
        NombreVariante.fromInput(anterior.nombre).value,
        propuesta.nombre,
      );
      campo(
        '$etiqueta · Precio de venta',
        _importe(anterior.precioVentaMinor),
        _importe(propuesta.precioVentaMinor),
      );
      campo(
        '$etiqueta · Precio de coste',
        _importe(anterior.precioCosteMinor),
        _importe(propuesta.precioCosteMinor),
      );
      if (propuesta.offerPrice.establecer) {
        campo(
          '$etiqueta · Precio de oferta',
          anterior.offerPriceMinor == null
              ? 'Sin oferta'
              : _importe(anterior.offerPriceMinor),
          propuesta.offerPrice.valor == null
              ? 'Sin oferta'
              : _importe(propuesta.offerPrice.valor),
        );
      }
      campo(
        '$etiqueta · Código de barras',
        _texto(anterior.codigoBarras),
        propuesta.codigoBarras,
      );
    }
    return ExpansionTile(
      key: ValueKey('bulk_import_diff_${producto.productId}'),
      title: Text(producto.nombre),
      subtitle: Text(
        'Producto ${producto.productId} · ${producto.variantes.length} filas',
      ),
      childrenPadding: const EdgeInsets.all(12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: diferencias,
    );
  }
}
