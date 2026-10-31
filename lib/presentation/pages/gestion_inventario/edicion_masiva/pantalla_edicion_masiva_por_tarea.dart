import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import '../../../../application/edicion_masiva/catalogo_edicion_masiva.dart';
import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../domain/proveedores/proveedor.dart';
import '../../../../domain/repositories/proveedor_repository.dart';
import 'borrador_edicion_masiva.dart';
import 'controlador_edicion_masiva.dart';
import 'detalle_proveedor_fila.dart';
import 'listado_edicion_masiva.dart';
import 'pantalla_revision_edicion_masiva.dart';
import 'recuperacion_edicion_masiva.dart';

/// Dos composiciones del mismo borrador: por tarea y recepción compacta.
/// La UI no importa Drift ni escribe en la
/// base; el guardado ocurre solo al confirmar la revisión.
class PantallaEdicionMasivaPorTarea extends StatefulWidget {
  const PantallaEdicionMasivaPorTarea({
    required this.catalogo,
    required this.comando,
    this.proveedorRepository,
    this.ahora,
    super.key,
  });

  final CatalogoEdicionMasiva catalogo;
  final EdicionMasivaCommandService comando;
  final ProveedorRepository? proveedorRepository;
  final DateTime Function()? ahora;

  @override
  State<PantallaEdicionMasivaPorTarea> createState() =>
      _PantallaEdicionMasivaPorTareaState();
}

class _PantallaEdicionMasivaPorTareaState
    extends State<PantallaEdicionMasivaPorTarea>
    with WidgetsBindingObserver {
  static const _busquedaDebounce = Duration(milliseconds: 200);

  late final ControladorEdicionMasiva _controller;
  final _busquedaController = TextEditingController();
  final _busquedaFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _busquedaTimer;
  bool _dialogoSalida = false;
  StreamSubscription<List<Proveedor>>? _proveedoresSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ControladorEdicionMasiva(
      catalogo: widget.catalogo,
      comando: widget.comando,
      ahora: widget.ahora,
    );
    unawaited(_controller.buscar());
    unawaited(_controller.consultarPendientes());
    _proveedoresSub = widget.proveedorRepository?.watchProveedores().listen(
      _controller.proveedoresActualizados,
      onError: _controller.falloProveedores,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busquedaTimer?.cancel();
    unawaited(_proveedoresSub?.cancel());
    _busquedaController.dispose();
    _busquedaFocus.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EDICIÓN MASIVA'),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('edicion_masiva_recuperacion'),
            tooltip: 'Capturas confirmadas y recuperación',
            icon: const Icon(Icons.history),
            onPressed: _abrirRecuperacion,
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: _alVolver,
        child: Column(
          children: [
            Expanded(
              child: ListadoEdicionMasiva(
                controller: _controller,
                scrollController: _scrollController,
                encabezado: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: TextField(
                        key: const Key('edicion_masiva_busqueda'),
                        controller: _busquedaController,
                        focusNode: _busquedaFocus,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Buscar artículo o variante',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _alBuscar,
                      ),
                    ),
                    _controles(),
                  ],
                ),
                onSiguiente: _enfocarSiguiente,
                onEnfocado: _campoEnfocado,
                onDetalleProveedor: _abrirDetalle,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _controller,
                    _controller.contador,
                  ]),
                  builder: (context, _) => ElevatedButton(
                    key: const Key('edicion_masiva_revisar'),
                    onPressed:
                        _controller.tieneCapturas && !_controller.guardando
                        ? _abrirRevision
                        : null,
                    child: Text(
                      _controller.guardando
                          ? 'Terminando guardado…'
                          : 'Revisar cambios (${_controller.modificadas})',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controles() {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _controller.contador]),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_controller.capturasPorRecuperar > 0 ||
                  _controller.errorRecuperacion != null)
                TextButton(
                  key: const Key('edicion_masiva_aviso_recuperacion'),
                  onPressed: _abrirRecuperacion,
                  child: Text(
                    _controller.errorRecuperacion != null
                        ? 'No se pudo consultar el diario. Abrir recuperación'
                        : '${_controller.capturasPorRecuperar} capturas confirmadas pendientes. Abrir recuperación',
                  ),
                ),
              DropdownButtonFormField<VistaEdicionMasiva>(
                key: const Key('edicion_masiva_vista'),
                initialValue: _controller.vista,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vista',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: VistaEdicionMasiva.porTarea,
                    child: Text('Por tarea'),
                  ),
                  DropdownMenuItem(
                    value: VistaEdicionMasiva.recepcionCompacta,
                    child: Text('Recepción compacta'),
                  ),
                ],
                onChanged: (valor) {
                  if (valor == null) return;
                  FocusManager.instance.primaryFocus?.unfocus();
                  _controller.cambiarVista(valor);
                  setState(() {});
                },
              ),
              if (_controller.vista == VistaEdicionMasiva.porTarea)
                DropdownButtonFormField<TareaEdicionMasiva>(
                  key: const Key('edicion_masiva_tarea'),
                  initialValue: _controller.tarea,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tarea',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: TareaEdicionMasiva.venta,
                      child: Text('Precio de venta'),
                    ),
                    DropdownMenuItem(
                      value: TareaEdicionMasiva.oferta,
                      child: Text('Precio de oferta'),
                    ),
                    DropdownMenuItem(
                      value: TareaEdicionMasiva.costoProveedor,
                      child: Text('Costo estándar y proveedor'),
                    ),
                    DropdownMenuItem(
                      value: TareaEdicionMasiva.agregarExistencias,
                      child: Text('Agregar existencias'),
                    ),
                  ],
                  onChanged: (valor) {
                    if (valor == null) return;
                    _controller.cambiarTarea(valor);
                    setState(() {});
                  },
                ),
              if ((_controller.vista == VistaEdicionMasiva.recepcionCompacta ||
                      _controller.tarea == TareaEdicionMasiva.costoProveedor) &&
                  (_controller.proveedores.isNotEmpty ||
                      _controller.borrador.proveedorGlobal != null))
                DropdownButtonFormField<String>(
                  key: const Key('edicion_masiva_proveedor_global'),
                  initialValue: _proveedorGlobalSeleccionado(),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor predeterminado para nuevas capturas',
                    isDense: true,
                  ),
                  items: [
                    if (_controller.borrador.proveedorGlobal case final global?)
                      if (!_controller.proveedores.any((p) => p.id == global))
                        DropdownMenuItem(
                          value: global,
                          child: const Text('Proveedor no disponible'),
                        ),
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
                  ],
                  onChanged: (valor) {
                    _controller.elegirProveedorGlobal(
                      valor == null || valor.isEmpty ? null : valor,
                    );
                    setState(() {});
                  },
                ),
              if ((_controller.vista == VistaEdicionMasiva.recepcionCompacta ||
                      _controller.tarea == TareaEdicionMasiva.costoProveedor) &&
                  _controller.errorProveedores != null)
                const Text(
                  'No se pudieron cargar los proveedores. Puedes conservar el costo sin proveedor y volver a intentarlo después.',
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  FilterChip(
                    key: const Key('edicion_masiva_solo_cambios'),
                    label: const Text('Solo cambios'),
                    selected: _controller.soloCambios,
                    onSelected: (valor) {
                      _controller.cambiarSoloCambios(valor);
                      setState(() {});
                    },
                  ),
                  Text(
                    '${_controller.modificadas} modificadas',
                    key: const Key('edicion_masiva_contador_modificadas'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _proveedorGlobalSeleccionado() =>
      _controller.borrador.proveedorGlobal ?? '';

  void _alBuscar(String texto) {
    _busquedaTimer?.cancel();
    _busquedaTimer = Timer(_busquedaDebounce, () {
      if (!mounted) return;
      unawaited(_controller.cambiarBusqueda(texto));
    });
  }

  Future<void> _enfocarSiguiente(ClaveVariante clave) async {
    var filas = _controller.filasListadas;
    final indice = filas.indexWhere((f) => f.clave == clave);
    if (indice == filas.length - 1 &&
        _controller.hayMasPaginas &&
        !_controller.soloCambios) {
      await _controller.cargarMas();
      if (!mounted) return;
      filas = _controller.filasListadas;
    }
    var siguiente = indice + 1;
    while (siguiente < filas.length &&
        _controller.vista == VistaEdicionMasiva.porTarea &&
        _controller.tarea == TareaEdicionMasiva.agregarExistencias &&
        filas[siguiente].entrada == null) {
      siguiente++;
    }
    if (indice < 0 || siguiente >= filas.length) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final foco = _controller.foco(filas[siguiente].clave);
    for (var intento = 0; foco.context == null && intento < 12; intento++) {
      if (!_scrollController.hasClients) return;
      final posicion = _scrollController.position;
      _scrollController.jumpTo(
        (posicion.pixels + posicion.viewportDimension * .6).clamp(
          0,
          posicion.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    foco.requestFocus();
  }

  @override
  void didChangeMetrics() {
    final clave = _controller.borrador.seleccion;
    if (clave != null) _campoEnfocado(clave);
  }

  void _campoEnfocado(ClaveVariante clave) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final contexto = _controller
          .foco(clave, _controller.campoSeleccionado)
          .context;
      if (contexto == null) return;
      Scrollable.ensureVisible(
        contexto,
        duration: Duration.zero,
        alignment: 0.2,
      );
    });
  }

  Future<void> _abrirDetalle(ClaveVariante clave) =>
      DetalleProveedorFila.mostrar(
        context: context,
        controller: _controller,
        fila: _controller.filasListadas.firstWhere((f) => f.clave == clave),
      );

  Future<void> _abrirRecuperacion() async {
    if (_controller.guardando) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final revisar = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecuperacionEdicionMasiva(controller: _controller),
      ),
    );
    if (!mounted) return;
    if (revisar == true) await _abrirRevision();
    if (!mounted) return;
    await _controller.buscar();
    await _controller.consultarPendientes();
  }

  Future<void> _abrirRevision() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PantallaRevisionEdicionMasiva(controller: _controller),
      ),
    );
    if (!mounted) return;
    if (guardado == true) {
      await _controller.buscar();
      await _controller.consultarPendientes();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _controller.tieneCapturas
                ? 'Quedan cambios sin aplicar; se conserva lo capturado.'
                : 'Cambios guardados en este dispositivo.',
          ),
        ),
      );
    }
  }

  Future<void> _alVolver(bool didPop, Object? result) async {
    if (didPop || _dialogoSalida) return;
    if (!_controller.tieneCapturas) {
      Navigator.of(context).pop(result);
      return;
    }
    _dialogoSalida = true;
    final descartar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: Text(
          'Hay ${_controller.modificadas} variantes con cambios sin guardar. '
          'Puedes continuar editando o descartar la captura.',
        ),
        actions: [
          TextButton(
            key: const Key('edicion_masiva_continuar'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar'),
          ),
          TextButton(
            key: const Key('edicion_masiva_descartar'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    _dialogoSalida = false;
    if (descartar != true || !mounted) return;
    _controller.descartarCapturas();
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
