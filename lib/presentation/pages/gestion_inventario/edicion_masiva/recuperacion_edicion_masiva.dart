import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/registro_operacion_masiva.dart';
import 'controlador_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';
import 'resultados_edicion_masiva.dart';

/// Consulta el diario existente sin ejecutar al abrir. Las operaciones aplicadas
/// se muestran junto a las pendientes para conservar el contexto de la captura.
class RecuperacionEdicionMasiva extends StatefulWidget {
  const RecuperacionEdicionMasiva({required this.controller, super.key});
  final ControladorEdicionMasiva controller;

  @override
  State<RecuperacionEdicionMasiva> createState() =>
      _RecuperacionEdicionMasivaState();
}

class _RecuperacionEdicionMasivaState extends State<RecuperacionEdicionMasiva> {
  late Future<List<RegistroOperacionMasiva>> _registros;
  bool _ocupada = false;

  @override
  void initState() {
    super.initState();
    _registros = widget.controller.registros();
  }

  Future<void> _accion(Future<void> Function() action) async {
    if (_ocupada) return;
    setState(() => _ocupada = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeLegibleEdicionMasiva(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _ocupada = false;
          _registros = widget.controller.registros();
        });
      }
    }
  }

  Future<void> _continuar(String batchId) => _accion(() async {
    final resultados = await widget.controller.continuarCaptura(batchId);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ResultadosEdicionMasiva(
          controller: widget.controller,
          resultados: resultados,
        ),
      ),
    );
  });

  Future<void> _revisar(String batchId) => _accion(() async {
    await widget.controller.recuperarParaRevision(batchId);
    if (mounted) Navigator.of(context).pop(true);
  });

  Future<void> _cerrar(String batchId) async {
    final cerrar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar pendientes'),
        content: const Text(
          'Se retirarán únicamente los productos sin aplicar de esta captura. Los commits realizados y su evidencia se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar pendientes'),
          ),
        ],
      ),
    );
    if (cerrar != true || !mounted) return;
    await _accion(() => widget.controller.cerrarCaptura(batchId));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !_ocupada,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _ocupada) widget.controller.cancelarGuardado();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('CAPTURAS CONFIRMADAS')),
        body: FutureBuilder<List<RegistroOperacionMasiva>>(
          future: _registros,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(mensajeLegibleEdicionMasiva(snapshot.error!)),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final grupos = <String, List<RegistroOperacionMasiva>>{};
            for (final r in snapshot.data!) {
              grupos.putIfAbsent(r.operacion.batchId, () => []).add(r);
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Continuar revalida las bases y devuelve los resultados ya aplicados. No se ejecuta nada al abrir esta pantalla.',
                ),
                if (grupos.isEmpty) const Text('No hay capturas confirmadas.'),
                for (final grupo in grupos.entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Captura ${grupo.key}'),
                          Text(
                            '${grupo.value.first.confirmadaAt.toLocal()} · ${grupo.value.first.operacion.modo.storageValue}',
                          ),
                          for (final r in grupo.value)
                            Text(
                              '${widget.controller.nombreProducto(r.operacion.productId)}: ${switch (r.estado) {
                                EstadoOperacionMasiva.confirmada => 'Pendiente de ejecutar',
                                EstadoOperacionMasiva.aplicada => 'Aplicado localmente',
                                EstadoOperacionMasiva.cerrada => 'Omitido por cierre explícito',
                              }}',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                key: Key(
                                  'edicion_masiva_continuar_${grupo.key}',
                                ),
                                onPressed: _ocupada
                                    ? null
                                    : () => _continuar(grupo.key),
                                child: const Text('Continuar / ver resultados'),
                              ),
                              if (grupo.value.any(
                                (r) =>
                                    r.estado ==
                                    EstadoOperacionMasiva.confirmada,
                              )) ...[
                                TextButton(
                                  key: Key(
                                    'edicion_masiva_recuperar_${grupo.key}',
                                  ),
                                  onPressed: _ocupada
                                      ? null
                                      : () => _revisar(grupo.key),
                                  child: const Text('Revisar pendientes'),
                                ),
                                TextButton(
                                  onPressed: _ocupada
                                      ? null
                                      : () => _cerrar(grupo.key),
                                  child: const Text('Cerrar pendientes'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: widget.controller.guardando
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Aplicando ${widget.controller.productosGuardados}/${widget.controller.productosAGuardar}…',
                      ),
                      TextButton(
                        onPressed: widget.controller.cancelacionSolicitada
                            ? null
                            : widget.controller.cancelarGuardado,
                        child: Text(
                          widget.controller.cancelacionSolicitada
                              ? 'Esperando transacción…'
                              : 'Detener pendientes',
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}
