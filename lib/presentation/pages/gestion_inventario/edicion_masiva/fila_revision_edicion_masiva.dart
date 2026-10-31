import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/cambio_variante_masiva.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import 'controlador_edicion_masiva.dart';
import 'fila_revision_masiva.dart';

/// Revisión de una variante: valores antes/después en texto, proveedor
/// efectivo, fecha, unidades, saldo previsto y errores explicados.
class FilaRevisionEdicionMasiva extends StatelessWidget {
  const FilaRevisionEdicionMasiva({
    required this.controller,
    required this.fila,
    required this.onRetirar,
    super.key,
  });

  static const _importes = ImporteComercialCodec();
  static const _cantidades = InventoryQuantityCodec();

  final ControladorEdicionMasiva controller;
  final FilaRevisionMasiva fila;
  final VoidCallback? onRetirar;

  @override
  Widget build(BuildContext context) {
    final original = fila.captura.original;
    final id = original.clave.variantId;
    final nombre =
        original.nombreVariante == null || original.nombreVariante!.isEmpty
        ? original.nombreProducto
        : '${original.nombreProducto} · ${original.nombreVariante}';
    final cambio = fila.cambio;
    return Card(
      key: ValueKey('edicion_masiva_revision_fila_$id'),
      shape: const RoundedRectangleBorder(),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(_estado, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (original.configuracionVenta case MeasuredSaleConfiguration(
              :final priceReferenceQuantityAtomic,
            ))
              Text(
                'Precios por ${original.unidadVenta == null ? priceReferenceQuantityAtomic : _cantidades.formatAtomic(priceReferenceQuantityAtomic, original.unidadVenta!)} ${original.unidadVenta?.simbolo ?? "unidades de venta"}',
              ),
            if (cambio != null) ..._cambios(cambio),
            if (fila.captura.proveedorCapturado) _proveedor(),
            if (fila.errores.isNotEmpty) ...[
              if (fila.captura.venta != null)
                Text('Venta capturada: «${fila.captura.venta}»'),
              if (fila.captura.costo != null)
                Text('Costo capturado: «${fila.captura.costo}»'),
              if (fila.captura.cantidad != null)
                Text('Cantidad capturada: «${fila.captura.cantidad}»'),
            ],
            if (fila.actual != null &&
                fila.errores.containsKey(CampoEdicionMasiva.base))
              ..._fotoNueva(context),
            for (final entry in fila.errores.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.value,
                  key: Key('edicion_masiva_error_${entry.key.name}_$id'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('edicion_masiva_retirar_$id'),
                onPressed: onRetirar,
                child: const Text('Retirar fila'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _estado => switch (fila.estado) {
    EstadoFilaMasiva.sinCambios => 'Sin cambios',
    EstadoFilaMasiva.cambios => 'Con cambios',
    EstadoFilaMasiva.error => 'Requiere revisión',
  };

  List<Widget> _cambios(CambioVarianteMasiva cambio) {
    final widgets = <Widget>[];
    if (cambio.oferta.establecer) {
      widgets.add(
        Text(
          'Oferta: ${fila.captura.original.ofertaMinor == null ? "Sin oferta" : _importes.format(fila.captura.original.ofertaMinor!)} → ${cambio.oferta.valor == null ? "Sin oferta" : _importes.format(cambio.oferta.valor!)}',
        ),
      );
    }
    if (cambio.venta.establecer) {
      widgets.add(
        Text(
          'Precio de venta: ${_importes.format(fila.captura.original.ventaMinor)} '
          '→ ${_importes.format(cambio.venta.valor)}',
        ),
      );
    }
    final costoActual = fila.captura.original.costoMinor;
    if (cambio.costo.establecer) {
      widgets.add(
        Text(
          'Costo estándar: ${costoActual == null ? 'desconocido' : _importes.format(costoActual)} '
          '→ ${_importes.format(cambio.costo.valor)}',
        ),
      );
    }
    final entrada = cambio.entrada;
    if (entrada != null) {
      final unidad = entrada.base.unidad;
      widgets.add(
        Text(
          'Entrada: +${_cantidades.formatAtomic(entrada.cantidadAtomic, unidad)} '
          '${unidad.simbolo} · saldo actual '
          '${_cantidades.formatAtomic(entrada.base.existenciaAtomic, unidad)} → '
          'previsto '
          '${_cantidades.formatAtomic(entrada.existenciaPrevistaAtomic, unidad)} '
          '${unidad.simbolo}',
        ),
      );
    }
    return widgets;
  }

  Widget _proveedor() {
    final captura = fila.captura;
    final id = captura.proveedorId;
    if (id == null) {
      return const Text('Proveedor: sin proveedor; solo costo estándar.');
    }
    final propuesta = fila.cambio?.precioProveedor;
    final actual = captura.original.proveedores
        .where((p) => p.proveedorId == id)
        .firstOrNull;
    final fecha =
        propuesta?.fechaInformadaMs ??
        actual?.fechaInformadaMs ??
        captura.fechaInformada?.millisecondsSinceEpoch;
    return Text(
      'Proveedor: ${controller.nombreProveedor(id)} · '
      '${actual == null ? "Pareja nueva" : "Precio actual ${_importes.format(actual.precioInformadoMenor)}"}'
      '${propuesta == null ? " · precio conservado" : " → ${_importes.format(propuesta.precioInformadoMenor)}"}'
      '${fecha == null ? "" : " · fecha ${_fecha(fecha)}"}',
      key: Key(
        'edicion_masiva_revision_proveedor_${captura.original.clave.variantId}',
      ),
    );
  }

  List<Widget> _fotoNueva(BuildContext context) {
    final actual = fila.actual!;
    final costo = actual.costoMinor;
    final entrada = actual.entrada;
    final anterior = fila.captura.original.entrada;
    String? prevision;
    if (entrada != null &&
        anterior != null &&
        entrada.recurso.id == anterior.recurso.id &&
        entrada.unidad.id == anterior.unidad.id &&
        entrada.unidad.factorAtomico == anterior.unidad.factorAtomico &&
        entrada.unidad.dimension == anterior.unidad.dimension) {
      final texto = fila.captura.cantidad?.trim() ?? '';
      if (texto.isNotEmpty) {
        try {
          final cantidad = _cantidades.parseNonNegativeAtomic(
            texto,
            entrada.unidad,
          );
          prevision =
              'Previsión sobre estado nuevo: '
              '${_cantidades.formatAtomic(entrada.existenciaAtomic, entrada.unidad)} + '
              '${_cantidades.formatAtomic(cantidad, entrada.unidad)} = '
              '${_cantidades.formatAtomic(entrada.existenciaAtomic + cantidad, entrada.unidad)} ${entrada.unidad.simbolo}. '
              'Requiere nueva revisión.';
        } on FormatException {
          // La cantidad cruda y su error permanecen visibles en la revisión.
        }
      }
    }
    return [
      if (prevision != null) Text(prevision),
      Text(
        'Estado nuevo: venta ${_importes.format(actual.ventaMinor)} · '
        'costo ${costo == null ? 'desconocido' : _importes.format(costo)}'
        '${actual.entrada == null ? '' : ' · saldo ${_cantidades.formatAtomic(actual.entrada!.existenciaAtomic, actual.entrada!.unidad)} ${actual.entrada!.unidad.simbolo}'}',
        key: Key(
          'edicion_masiva_revision_actual_${fila.captura.original.clave.variantId}',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  String _fecha(int milliseconds) {
    final fecha = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}
