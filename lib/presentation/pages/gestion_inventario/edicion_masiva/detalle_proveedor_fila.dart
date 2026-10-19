import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../domain/articulos/proveedor_variante.dart';
import 'controlador_edicion_masiva.dart';

/// Detalle de una fila: proveedor explícito y fecha de captura. Aplica solo a
/// esta variante y nunca retira las demás parejas; la edición es de borrador.
class DetalleProveedorFila extends StatefulWidget {
  const DetalleProveedorFila({
    required this.controller,
    required this.fila,
    super.key,
  });

  final ControladorEdicionMasiva controller;
  final FilaCatalogoMasivo fila;

  static Future<void> mostrar({
    required BuildContext context,
    required ControladorEdicionMasiva controller,
    required FilaCatalogoMasivo fila,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: DetalleProveedorFila(controller: controller, fila: fila),
    ),
  );

  @override
  State<DetalleProveedorFila> createState() => _DetalleProveedorFilaState();
}

class _DetalleProveedorFilaState extends State<DetalleProveedorFila> {
  static const _importes = ImporteComercialCodec();

  ClaveVariante get _clave => widget.fila.clave;
  ControladorEdicionMasiva get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final original = widget.fila;
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        _controller.notificadorFila(_clave),
      ]),
      builder: (context, _) {
        final captura = _controller.borrador.filas[_clave];
        final proveedorId = captura?.proveedorCapturado == true
            ? captura!.proveedorId
            : _controller.borrador.proveedorGlobal;
        final costo = original.costoMinor;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detalle de la variante',
                  key: const Key('edicion_masiva_detalle_titulo'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  original.nombreVariante == null ||
                          original.nombreVariante!.isEmpty
                      ? original.nombreProducto
                      : '${original.nombreProducto} · ${original.nombreVariante}',
                ),
                const SizedBox(height: 8),
                Text(
                  costo == null
                      ? 'Costo actual: desconocido'
                      : 'Costo actual: ${_importes.format(costo)}',
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('edicion_masiva_detalle_proveedor'),
                  initialValue: proveedorId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor de esta fila',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin proveedor'),
                    ),
                    for (final proveedor in _controller.proveedores)
                      DropdownMenuItem(
                        value: proveedor.id,
                        child: Text(
                          proveedor.nombre,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_proveedorNoDisponible(proveedorId))
                      DropdownMenuItem(
                        value: proveedorId,
                        child: const Text('Proveedor no disponible'),
                      ),
                  ],
                  onChanged: (valor) => _controller.editarProveedorFila(
                    _clave,
                    valor == null || valor.isEmpty ? null : valor,
                  ),
                ),
                if (_parejaVigente(proveedorId) case final pareja?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Precio de la pareja: ${_importes.format(pareja.precioInformadoMenor)} · '
                      'Fecha: ${_fecha(pareja.fechaInformadaMs)}',
                    ),
                  ),
                if (costo == null && (captura?.costo?.trim().isEmpty ?? true))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Captura el costo para actualizar o crear la pareja con este proveedor.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fecha de captura: ${_fechaTexto(captura?.fechaInformada)}',
                        key: const Key('edicion_masiva_detalle_fecha'),
                      ),
                    ),
                    TextButton(
                      key: const Key('edicion_masiva_detalle_cambiar_fecha'),
                      onPressed: () => _elegirFecha(context),
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('edicion_masiva_detalle_cerrar'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _proveedorNoDisponible(String? capturado) =>
      capturado != null &&
      capturado.isNotEmpty &&
      !_controller.proveedores.any((p) => p.id == capturado);

  ProveedorVariante? _parejaVigente(String? proveedorId) {
    if (proveedorId == null) return null;
    for (final pareja in widget.fila.proveedores) {
      if (pareja.proveedorId == proveedorId) return pareja;
    }
    return null;
  }

  Future<void> _elegirFecha(BuildContext context) async {
    final actual =
        widget.controller.borrador.filas[_clave]?.fechaInformada ??
        DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (elegida == null ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final captura = widget.controller.borrador.filas[_clave];
    final proveedorId = captura?.proveedorCapturado == true
        ? captura!.proveedorId
        : widget.controller.borrador.proveedorGlobal;
    await widget.controller.editarProveedorFila(
      _clave,
      proveedorId,
      fecha: DateTime(elegida.year, elegida.month, elegida.day),
    );
  }

  String _fecha(int milliseconds) {
    final fecha = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return _fechaTexto(fecha);
  }

  String _fechaTexto(DateTime? fecha) {
    final value = fecha?.toLocal() ?? DateTime.now();
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}
