import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/clave_variante.dart';
import 'controlador_edicion_masiva.dart';
import 'fila_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';

/// Listado perezoso: construye solo las filas visibles y pide la siguiente
/// página al acercarse al final. No hidrata el catálogo completo.
class ListadoEdicionMasiva extends StatefulWidget {
  const ListadoEdicionMasiva({
    required this.controller,
    required this.scrollController,
    required this.onSiguiente,
    required this.onEnfocado,
    required this.encabezado,
    this.onDetalleProveedor,
    super.key,
  });

  final ControladorEdicionMasiva controller;
  final ScrollController scrollController;
  final Widget encabezado;
  final void Function(ClaveVariante clave) onSiguiente;
  final void Function(ClaveVariante clave) onEnfocado;
  final void Function(ClaveVariante clave)? onDetalleProveedor;

  @override
  State<ListadoEdicionMasiva> createState() => _ListadoEdicionMasivaState();
}

class _ListadoEdicionMasivaState extends State<ListadoEdicionMasiva> {
  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_alDesplazar);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_alDesplazar);
    super.dispose();
  }

  void _alDesplazar() {
    if (widget.scrollController.position.extentAfter < 240) {
      unawaited(widget.controller.cargarMas());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final filas = widget.controller.filasListadas;
        return CustomScrollView(
          key: const Key('edicion_masiva_listado'),
          controller: widget.scrollController,
          slivers: [
            SliverToBoxAdapter(child: widget.encabezado),
            if (widget.controller.errorCarga case final error?)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No se pudieron cargar los artículos: ${mensajeLegibleEdicionMasiva(error)}',
                        ),
                        TextButton(
                          onPressed: widget.controller.buscar,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  key: const Key('edicion_masiva_listado_vacio'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.controller.cargando
                          ? 'Cargando artículos…'
                          : 'No hay artículos que coincidan con la búsqueda.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                sliver: SliverList.builder(
                  itemCount: filas.length,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<ClaveVariante>) return null;
                    final index = filas.indexWhere((f) => f.clave == key.value);
                    return index < 0 ? null : index;
                  },
                  itemBuilder: (context, index) {
                    final fila = filas[index];
                    return FilaEdicionMasiva(
                      key: ValueKey(fila.clave),
                      controller: widget.controller,
                      fila: fila,
                      onSiguiente: () => widget.onSiguiente(fila.clave),
                      onEnfocado: () => widget.onEnfocado(fila.clave),
                      onDetalleProveedor: widget.onDetalleProveedor == null
                          ? null
                          : () => widget.onDetalleProveedor!(fila.clave),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
