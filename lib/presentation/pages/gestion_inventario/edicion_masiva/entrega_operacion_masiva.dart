import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/resultado_operacion_masiva.dart';
import '../../../../application/sync/models/sync_event.dart';
import 'controlador_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';

/// Lee la entrega actual de los eventos originales. Consultar o refrescar
/// nunca ejecuta de nuevo comandos de recepción ni dispara transporte.
class EntregaOperacionMasiva extends StatefulWidget {
  const EntregaOperacionMasiva({
    required this.controller,
    required this.resultado,
    super.key,
  });
  final ControladorEdicionMasiva controller;
  final ResultadoOperacionMasiva resultado;

  @override
  State<EntregaOperacionMasiva> createState() => _EntregaOperacionMasivaState();
}

class _EntregaOperacionMasivaState extends State<EntregaOperacionMasiva> {
  late Future<List<SyncEvent>> _eventos;

  @override
  void initState() {
    super.initState();
    _eventos = widget.controller.comando.eventos(widget.resultado);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SyncEvent>>(
    future: _eventos,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Entrega por evento; catálogo y entradas se aceptan por separado.',
        ),
        if (snapshot.hasError)
          Text(
            'No se pudo consultar la entrega: ${mensajeLegibleEdicionMasiva(snapshot.error!)}',
          )
        else if (!snapshot.hasData)
          const Text('Consultando entrega…')
        else
          for (final evento in snapshot.data!)
            Text(
              '${evento.eventId == widget.resultado.catalogEventId ? "Catálogo" : "Entrada ${widget.resultado.entradas.indexWhere((e) => e.eventId == evento.eventId) + 1}"}: ${switch (evento.deliveryStatus) {
                'not_required' => 'Registro local; no requiere envío',
                'pending' => 'Pendiente de aceptación remota',
                'delivered' => 'Aceptado por el servidor',
                'conflict' => 'Conflicto; requiere atención',
                'rejected' => 'Rechazado por el servidor',
                _ => 'Entrega ${evento.deliveryStatus}',
              }}${evento.rejectionReason == null ? '' : ' · ${evento.rejectionReason}'}',
              key: Key('edicion_masiva_entrega_${evento.eventId}'),
            ),
        if (snapshot.data?.any(
              (e) =>
                  e.deliveryStatus == 'conflict' ||
                  e.deliveryStatus == 'rejected',
            ) ==
            true)
          const Text(
            'Hay partes sin aceptar. Los valores locales pueden haberse restaurado. Revisa cada parte antes de resolver; no repitas la entrada.',
          ),
        TextButton(
          onPressed: () => setState(() {
            _eventos = widget.controller.comando.eventos(widget.resultado);
          }),
          child: const Text('Actualizar entrega'),
        ),
      ],
    ),
  );
}
