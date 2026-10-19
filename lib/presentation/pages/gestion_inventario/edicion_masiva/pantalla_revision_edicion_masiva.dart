import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import 'controlador_edicion_masiva.dart';
import 'fila_revision_edicion_masiva.dart';
import 'fila_revision_masiva.dart';
import 'revision_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';
import 'resultados_edicion_masiva.dart';

/// Revisión de todo el borrador, incluidas las filas ocultas por búsqueda o
/// filtro. Preparar solo lee; confirmar usa el coordinador transaccional.
class PantallaRevisionEdicionMasiva extends StatefulWidget {
  const PantallaRevisionEdicionMasiva({required this.controller, super.key});

  final ControladorEdicionMasiva controller;

  @override
  State<PantallaRevisionEdicionMasiva> createState() =>
      _PantallaRevisionEdicionMasivaState();
}

class _PantallaRevisionEdicionMasivaState
    extends State<PantallaRevisionEdicionMasiva> {
  RevisionEdicionMasiva? _revision;
  Object? _errorPreparacion;
  var _preparando = false;
  var _guardando = false;

  ControladorEdicionMasiva get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  @override
  void dispose() {
    // Una salida durante el guardado detiene los productos no iniciados.
    _controller.cancelarGuardado(notificar: false);
    super.dispose();
  }

  Future<void> _preparar() async {
    setState(() {
      _preparando = true;
      _errorPreparacion = null;
    });
    try {
      final revision = await _controller.prepararRevision();
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _preparando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorPreparacion = error;
        _preparando = false;
      });
    }
  }

  Future<void> _guardar() async {
    final revision = _revision;
    if (revision == null || revision.tieneErrores || _guardando) return;
    setState(() => _guardando = true);
    List<ResultadoGuardadoMasivo> resultados;
    try {
      resultados = await _controller.guardar(revision);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeLegibleEdicionMasiva(error))),
      );
      return;
    }
    // Una ruta cerrada no navega con la respuesta tardía.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (resultados.isEmpty) {
      setState(() => _guardando = false);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ResultadosEdicionMasiva(
          controller: _controller,
          resultados: resultados,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final revision = _revision;
    final filas = revision?.filas ?? const <FilaRevisionMasiva>[];
    return PopScope(
      canPop: !_guardando,
      onPopInvokedWithResult: (didPop, _) {
        if (_guardando || didPop) _controller.cancelarGuardado();
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('REVISIÓN DE CAMBIOS'),
            centerTitle: true,
          ),
          body: Column(
            children: [
              if (revision != null) _resumen(context, revision),
              if (_errorPreparacion != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No se pudo preparar la revisión: '
                        '${mensajeLegibleEdicionMasiva(_errorPreparacion!)}',
                        key: const Key('edicion_masiva_error_preparacion'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (_preparando && revision == null)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      key: Key('edicion_masiva_preparando'),
                    ),
                  ),
                )
              else
                Expanded(
                  child: filas.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No hay cambios que revisar.',
                              key: Key('edicion_masiva_revision_vacia'),
                            ),
                          ),
                        )
                      : ListView(
                          key: const Key('edicion_masiva_revision_listado'),
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          children: [
                            if (!_guardando && _revision != null)
                              TextButton(
                                key: const Key('edicion_masiva_nueva_revision'),
                                onPressed: _preparando
                                    ? null
                                    : _revisarEstadoNuevo,
                                child: const Text('Revisar sobre estado nuevo'),
                              ),
                            ..._totalesEntradas(filas),
                            ..._agrupadas(filas),
                          ],
                        ),
                ),
              if (_errorPreparacion != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton(
                    key: const Key('edicion_masiva_reintentar_preparacion'),
                    onPressed: _preparar,
                    child: const Text('Reintentar'),
                  ),
                ),
              _acciones(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _acciones() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          TextButton(
            key: const Key('edicion_masiva_volver'),
            onPressed: _guardando ? null : () => Navigator.of(context).pop(),
            child: const Text('Volver'),
          ),
          if (_guardando) ...[
            TextButton(
              key: const Key('edicion_masiva_cancelar_guardado'),
              onPressed: _controller.cancelacionSolicitada
                  ? null
                  : _controller.cancelarGuardado,
              child: Text(
                _controller.cancelacionSolicitada
                    ? 'Esperando transacción…'
                    : 'Detener pendientes',
              ),
            ),
            Text(
              'Aplicando ${_controller.productosGuardados}/${_controller.productosAGuardar}…',
              key: const Key('edicion_masiva_progreso'),
            ),
          ],
          ElevatedButton(
            key: const Key('edicion_masiva_guardar'),
            onPressed: _puedeGuardar ? _guardar : null,
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );

  bool get _puedeGuardar {
    final revision = _revision;
    return !_guardando &&
        !_preparando &&
        _errorPreparacion == null &&
        revision != null &&
        !revision.tieneErrores &&
        revision.filas.isNotEmpty;
  }

  Widget _resumen(BuildContext context, RevisionEdicionMasiva revision) {
    final conCambios = revision.filas
        .where((f) => f.estado == EstadoFilaMasiva.cambios)
        .length;
    final conError = revision.filas
        .where((f) => f.estado == EstadoFilaMasiva.error)
        .length;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$conCambios variantes con cambios · $conError con errores',
              key: const Key('edicion_masiva_resumen'),
            ),
            const Text(
              'Incluye todo el borrador, también los cambios ocultos en la captura.',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _totalesEntradas(List<FilaRevisionMasiva> filas) {
    final totales = <String, BigInt>{};
    final unidades = <String, UnidadInventario>{};
    for (final fila in filas) {
      final entrada = fila.cambio?.entrada;
      if (entrada == null) continue;
      final unidad = entrada.base.unidad;
      unidades[unidad.id] = unidad;
      totales.update(
        unidad.id,
        (suma) => suma + BigInt.from(entrada.cantidadAtomic),
        ifAbsent: () => BigInt.from(entrada.cantidadAtomic),
      );
    }
    return [
      for (final total in totales.entries)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Total de entradas: +${_totalEnUnidad(total.value, unidades[total.key]!)} ${unidades[total.key]!.simbolo}',
            key: Key('edicion_masiva_total_entradas_${total.key}'),
          ),
        ),
    ];
  }

  String _totalEnUnidad(BigInt cantidad, UnidadInventario unidad) {
    final factor = BigInt.from(unidad.factorAtomico);
    final resto = cantidad.remainder(factor).toInt();
    final entero = cantidad ~/ factor;
    return resto == 0
        ? '$entero'
        : '$entero${const InventoryQuantityCodec().formatAtomic(resto, unidad).substring(1)}';
  }

  List<Widget> _agrupadas(List<FilaRevisionMasiva> filas) {
    final widgets = <Widget>[];
    String? productoActual;
    for (final fila in filas) {
      final productId = fila.captura.original.clave.productId;
      if (productId != productoActual) {
        productoActual = productId;
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _controller.nombreProducto(productId),
              key: Key('edicion_masiva_revision_producto_$productId'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      }
      widgets.add(
        FilaRevisionEdicionMasiva(
          controller: _controller,
          fila: fila,
          onRetirar: _guardando || _preparando
              ? null
              : () => _retirar(fila.captura.original.clave),
        ),
      );
    }
    return widgets;
  }

  Future<void> _revisarEstadoNuevo() async {
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva revisión'),
        content: const Text(
          'Se conservará lo escrito y se usará el estado actual como base. Las reservas pendientes anteriores se cerrarán. Revisa otra vez los valores y saldos antes de guardar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revisar estado actual'),
          ),
        ],
      ),
    );
    if (aceptar != true || !mounted) return;
    setState(() => _preparando = true);
    try {
      await _controller.revisarEstadoNuevo();
      if (mounted) await _preparar();
    } catch (error) {
      if (!mounted) return;
      setState(() => _preparando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeLegibleEdicionMasiva(error))),
      );
    }
  }

  Future<void> _retirar(ClaveVariante clave) async {
    _controller.retirarFila(clave);
    await _preparar();
  }
}
