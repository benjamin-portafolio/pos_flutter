import 'capturar_oferta_masiva.dart';
import '../../../../application/edicion_masiva/cambio_explicito.dart';
import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import 'fila_revision_masiva.dart';
import 'borrador_edicion_masiva.dart';
import 'controlador_edicion_masiva.dart';
import 'fila_edicion_form.dart';

/// Una variante por tarea o con costo/venta y entrada compactos. Los
/// controladores de texto pertenecen al controlador y viven por ID: filtrar o
/// reconstruir la lista no pierde capturas, foco ni selección.
class FilaEdicionMasiva extends StatefulWidget {
  const FilaEdicionMasiva({
    required this.controller,
    required this.fila,
    required this.onSiguiente,
    required this.onEnfocado,
    this.onDetalleProveedor,
    super.key,
  });

  final ControladorEdicionMasiva controller;
  final FilaCatalogoMasivo fila;
  final VoidCallback onSiguiente;
  final VoidCallback onEnfocado;
  final VoidCallback? onDetalleProveedor;

  @override
  State<FilaEdicionMasiva> createState() => _FilaEdicionMasivaState();
}

class _FilaEdicionMasivaState extends State<FilaEdicionMasiva> {
  static const _importes = ImporteComercialCodec();
  static const _cantidades = InventoryQuantityCodec();

  ClaveVariante get _clave => widget.fila.clave;
  String get _id => _clave.variantId;
  final _escuchas = <FocusNode, VoidCallback>{};

  @override
  void initState() {
    super.initState();
    for (final campo in CampoTextoEdicion.values) {
      final foco = widget.controller.foco(_clave, campo);
      void alFoco() {
        if (!foco.hasFocus) return;
        widget.controller.borrador.seleccion = _clave;
        widget.controller.campoSeleccionado = campo;
        widget.onEnfocado();
      }

      _escuchas[foco] = alFoco;
      foco.addListener(alFoco);
    }
  }

  @override
  void dispose() {
    for (final entry in _escuchas.entries) {
      entry.key.removeListener(entry.value);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borrador = widget.controller.borrador;
    final estilo = Theme.of(context).textTheme.bodySmall;
    return Card(
      key: ValueKey('edicion_masiva_fila_$_id'),
      shape: const RoundedRectangleBorder(),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListenableBuilder(
          listenable: widget.controller.notificadorFila(_clave),
          builder: (context, _) {
            final capturada = borrador.filas[_clave];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _nombre,
                        key: Key('edicion_masiva_nombre_$_id'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (widget.controller.modificada(_clave))
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'Modificado',
                          key: Key('edicion_masiva_modificada_$_id'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.fila.configuracionVenta
                    case MeasuredSaleConfiguration(
                      :final priceReferenceQuantityAtomic,
                    ))
                  Text(
                    'Precios por ${widget.fila.unidadVenta == null ? priceReferenceQuantityAtomic : _cantidades.formatAtomic(priceReferenceQuantityAtomic, widget.fila.unidadVenta!)} ${widget.fila.unidadVenta?.simbolo ?? "unidades de venta"}',
                    style: estilo,
                  ),
                ..._contenido(context, capturada, estilo),
                if (widget.controller.errorCaptura(_clave) case final error?)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _nombre {
    final variante = widget.fila.nombreVariante;
    return variante == null || variante.isEmpty
        ? widget.fila.nombreProducto
        : '${widget.fila.nombreProducto} · $variante';
  }

  List<Widget> _contenido(
    BuildContext context,
    FilaEdicionForm? capturada,
    TextStyle? estilo,
  ) {
    if (widget.controller.vista == VistaEdicionMasiva.recepcionCompacta) {
      return _compacta(context, capturada, estilo);
    }
    switch (widget.controller.tarea) {
      case TareaEdicionMasiva.oferta:
        return [
          Text(
            widget.fila.ofertaMinor == null
                ? 'Sin oferta'
                : 'Oferta actual: ${_importes.format(widget.fila.ofertaMinor!)}',
          ),
          TextButton(
            key: ValueKey('offer_edit_${widget.fila.clave.variantId}'),
            onPressed: widget.controller.guardando
                ? null
                : () async {
                    final change = await capturarOfertaMasiva(
                      context,
                      actual: widget.fila.ofertaMinor,
                      cambio:
                          capturada?.oferta ??
                          const CambioExplicito.conservar(),
                    );
                    if (change != null) {
                      await widget.controller.editarOferta(
                        widget.fila.clave,
                        change,
                      );
                    }
                  },
            child: Text(
              capturada?.oferta.establecer != true
                  ? 'Configurar oferta'
                  : capturada!.oferta.valor == null
                  ? 'Retirar oferta'
                  : 'Oferta propuesta: ${capturada.oferta.valor}',
            ),
          ),
        ];
      case TareaEdicionMasiva.venta:
        final venta = capturada?.venta;
        return [
          Text('Actual: ${_importes.format(widget.fila.ventaMinor)}'),
          if (venta != null) Text('Nuevo: $venta', style: estilo),
          _campo(
            context,
            campo: CampoTextoEdicion.venta,
            etiqueta: 'Precio de venta',
          ),
        ];
      case TareaEdicionMasiva.costoProveedor:
        final costo = widget.fila.costoMinor;
        final costoCapturado = capturada?.costo;
        return [
          Text(
            costo == null
                ? 'Costo actual: desconocido'
                : 'Costo actual: ${_importes.format(costo)}',
          ),
          if (costoCapturado != null)
            Text('Nuevo: $costoCapturado', style: estilo),
          _campo(
            context,
            campo: CampoTextoEdicion.costo,
            etiqueta: 'Costo estándar',
          ),
          Row(
            children: [
              Expanded(child: Text(_proveedorEfectivo, style: estilo)),
              TextButton(
                key: Key('edicion_masiva_detalle_$_id'),
                onPressed: widget.controller.guardando
                    ? null
                    : widget.onDetalleProveedor,
                child: const Text('Detalle'),
              ),
            ],
          ),
        ];
      case TareaEdicionMasiva.agregarExistencias:
        final entrada = widget.fila.entrada;
        if (entrada == null) {
          return [
            Text(
              widget.fila.impedimentoEntrada ?? 'Entrada no disponible.',
              key: Key('edicion_masiva_entrada_bloqueada_$_id'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            Text(
              'Los cambios comerciales siguen disponibles en esta fila.',
              style: estilo,
            ),
          ];
        }
        final unidad = entrada.unidad;
        final cantidad = capturada?.cantidad;
        return [
          Text('Unidad: ${unidad.nombre} (${unidad.simbolo})'),
          if (cantidad != null) Text('Nuevo: $cantidad', style: estilo),
          _campo(
            context,
            campo: CampoTextoEdicion.cantidad,
            etiqueta: 'Cantidad a agregar',
          ),
          Text(
            _saldoPrevisto(cantidad),
            key: Key('edicion_masiva_previsto_$_id'),
            style: estilo,
          ),
        ];
    }
  }

  List<Widget> _compacta(
    BuildContext context,
    FilaEdicionForm? captura,
    TextStyle? estilo,
  ) {
    final original = captura?.original ?? widget.fila;
    final entrada = original.entrada;
    String cantidad(int valor) =>
        _cantidades.formatAtomic(valor, entrada!.unidad);
    String previsto() {
      try {
        final texto = captura?.cantidad?.trim() ?? '';
        final delta = texto.isEmpty
            ? 0
            : _cantidades.parseNonNegativeAtomic(texto, entrada!.unidad);
        return cantidad(entrada!.existenciaAtomic + delta);
      } on FormatException {
        return 'Por corregir';
      }
    }

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _campo(
                  context,
                  campo: CampoTextoEdicion.costo,
                  etiqueta: 'Costo estándar',
                ),
                Text(
                  'Actual: ${original.costoMinor == null ? "desconocido" : _importes.format(original.costoMinor!)}',
                  style: estilo,
                ),
                if (captura?.costo != null)
                  Text('Nuevo: ${captura!.costo}', style: estilo),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _campo(
                  context,
                  campo: CampoTextoEdicion.venta,
                  etiqueta: 'Precio de venta',
                ),
                Text(
                  'Actual: ${_importes.format(original.ventaMinor)}',
                  style: estilo,
                ),
                if (captura?.venta != null)
                  Text('Nuevo: ${captura!.venta}', style: estilo),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (entrada != null) ...[
        Text(
          'Ingreso en ${entrada.unidad.nombre} (${entrada.unidad.simbolo})',
          style: estilo,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final existencias = Text(
              'Existencias\n${cantidad(entrada.existenciaAtomic)} ${entrada.unidad.simbolo}',
            );
            final ingreso = _campo(
              context,
              campo: CampoTextoEdicion.cantidad,
              etiqueta: 'A agregar',
            );
            final saldo = Text(
              'Previsto\n${previsto()} ${entrada.unidad.simbolo}',
              key: Key('edicion_masiva_previsto_$_id'),
            );
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(320)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: existencias),
                      const SizedBox(width: 8),
                      Expanded(child: saldo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ingreso,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: existencias),
                const SizedBox(width: 8),
                Expanded(child: ingreso),
                const SizedBox(width: 8),
                Expanded(child: saldo),
              ],
            );
          },
        ),
      ] else
        Text(
          original.impedimentoEntrada ?? 'Entrada no disponible.',
          key: Key('edicion_masiva_entrada_bloqueada_$_id'),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: Key('edicion_masiva_detalle_$_id'),
          onPressed: widget.controller.guardando
              ? null
              : widget.onDetalleProveedor,
          child: Text(
            captura?.proveedorCapturado == true &&
                    captura?.proveedorId !=
                        widget.controller.borrador.proveedorGlobal
                ? 'Detalle · proveedor propio'
                : 'Detalle · proveedor y fecha',
          ),
        ),
      ),
    ];
  }

  Widget _campo(
    BuildContext context, {
    required CampoTextoEdicion campo,
    required String etiqueta,
  }) {
    final errores = widget.controller.erroresFila(_clave);
    final errorCampo = switch (campo) {
      CampoTextoEdicion.venta => errores[CampoEdicionMasiva.venta],
      CampoTextoEdicion.costo => errores[CampoEdicionMasiva.costo],
      CampoTextoEdicion.cantidad => errores[CampoEdicionMasiva.cantidad],
    };
    return TextField(
      key: Key('edicion_masiva_${campo.name}_$_id'),
      controller: widget.controller.controladorTexto(
        _clave,
        campo,
        original: widget.fila,
      ),
      focusNode: widget.controller.foco(_clave, campo),
      enabled: !widget.controller.guardando,
      keyboardType: TextInputType.numberWithOptions(
        decimal:
            campo != CampoTextoEdicion.cantidad ||
            (widget.fila.entrada?.unidad.maximosDecimales ?? 0) > 0,
      ),
      textInputAction: TextInputAction.next,
      scrollPadding: const EdgeInsets.only(bottom: 96, top: 24),
      decoration: InputDecoration(
        labelText: etiqueta,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        errorText: errorCampo,
        errorMaxLines: 3,
      ),
      onChanged: (texto) => _editar(campo, texto),
      onSubmitted: (_) {
        if (widget.controller.vista == VistaEdicionMasiva.recepcionCompacta) {
          if (campo == CampoTextoEdicion.costo) {
            widget.controller
                .foco(_clave, CampoTextoEdicion.venta)
                .requestFocus();
            return;
          }
          if (campo == CampoTextoEdicion.venta && widget.fila.entrada != null) {
            widget.controller
                .foco(_clave, CampoTextoEdicion.cantidad)
                .requestFocus();
            return;
          }
        }
        widget.onSiguiente();
      },
    );
  }

  Future<void> _editar(CampoTextoEdicion campo, String texto) {
    switch (campo) {
      case CampoTextoEdicion.venta:
        return widget.controller.editarVenta(_clave, texto);
      case CampoTextoEdicion.costo:
        return widget.controller.editarCosto(_clave, texto);
      case CampoTextoEdicion.cantidad:
        return widget.controller.editarCantidad(_clave, texto);
    }
  }

  String get _proveedorEfectivo {
    final capturada = widget.controller.borrador.filas[_clave];
    if (capturada?.proveedorCapturado == true) {
      final id = capturada!.proveedorId;
      return id == null
          ? 'Proveedor: sin proveedor'
          : 'Proveedor: ${widget.controller.nombreProveedor(id)}';
    }
    final global = widget.controller.borrador.proveedorGlobal;
    return global == null
        ? 'Sin proveedor seleccionado'
        : 'Se usará: ${widget.controller.nombreProveedor(global)} (predeterminado)';
  }

  String _saldoPrevisto(String? texto) {
    final entrada = widget.fila.entrada;
    final unidad = entrada!.unidad;
    final capturado = texto?.trim() ?? '';
    if (capturado.isEmpty) {
      return 'Saldo actual: ${_cantidades.formatAtomic(entrada.existenciaAtomic, unidad)} ${unidad.simbolo}';
    }
    try {
      final cantidad = _cantidades.parseNonNegativeAtomic(capturado, unidad);
      final previsto = entrada.existenciaAtomic + cantidad;
      return 'Saldo actual: ${_cantidades.formatAtomic(entrada.existenciaAtomic, unidad)} · '
          'Previsto: ${_cantidades.formatAtomic(previsto, unidad)} ${unidad.simbolo}';
    } on FormatException {
      return 'Saldo actual: ${_cantidades.formatAtomic(entrada.existenciaAtomic, unidad)} ${unidad.simbolo}';
    }
  }
}
