import 'package:flutter/material.dart';

import '../../../../application/edicion_masiva/resultado_operacion_masiva.dart';
import 'entrega_operacion_masiva.dart';
import 'controlador_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';

/// Resultado del guardado local por producto. El commit local no equivale a
/// aceptación remota: la entrega sigue los mecanismos existentes por evento.
class ResultadosEdicionMasiva extends StatelessWidget {
  const ResultadosEdicionMasiva({
    required this.controller,
    required this.resultados,
    super.key,
  });

  final ControladorEdicionMasiva controller;
  final List<ResultadoGuardadoMasivo> resultados;

  @override
  Widget build(BuildContext context) {
    final aplicadas = resultados.where((r) => r.aplicada).length;
    return Scaffold(
      appBar: AppBar(title: const Text('RESULTADOS'), centerTitle: true),
      body: ListView(
        key: const Key('edicion_masiva_resultados'),
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            '$aplicadas de ${resultados.length} productos aplicados '
            'en este dispositivo.',
            key: const Key('edicion_masiva_resultado_resumen'),
          ),
          Text(
            '${resultados.where((r) => r.estado == EstadoGuardadoMasivo.omitida).length} omitidos · '
            '${resultados.where((r) => r.estado == EstadoGuardadoMasivo.fallida).length} fallidos · '
            '${resultados.where((r) => r.estado == EstadoGuardadoMasivo.pendiente).length} pendientes de ejecutar.',
            key: const Key('edicion_masiva_resultado_conteos'),
          ),
          const SizedBox(height: 8),
          for (final resultado in resultados)
            Card(
              key: Key('edicion_masiva_resultado_${resultado.productId}'),
              shape: const RoundedRectangleBorder(),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.nombreProducto(resultado.productId),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (resultado.aplicada)
                      ..._aplicada(context, resultado.resultado!)
                    else if (resultado.estado == EstadoGuardadoMasivo.pendiente)
                      const Text(
                        'Pendiente de ejecutar; no se inició este producto.',
                      )
                    else if (resultado.estado == EstadoGuardadoMasivo.omitida)
                      const Text(
                        'Omitido; sin cambios ejecutables o cerrado explícitamente.',
                      )
                    else
                      Text(
                        'No aplicado: ${mensajeLegibleEdicionMasiva(resultado.error!)}',
                        key: Key(
                          'edicion_masiva_resultado_error_${resultado.productId}',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            key: const Key('edicion_masiva_listo'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hecho'),
          ),
        ),
      ),
    );
  }

  List<Widget> _aplicada(
    BuildContext context,
    ResultadoOperacionMasiva resultado,
  ) {
    return [
      Text(
        'Aplicado en este dispositivo.',
        key: Key('edicion_masiva_resultado_ok_${resultado.productId}'),
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      if (resultado.catalogEventId != null)
        const Text('Datos comerciales actualizados.'),
      if (resultado.entradas.isNotEmpty)
        Text('Entradas registradas: ${resultado.entradas.length}.'),
      EntregaOperacionMasiva(controller: controller, resultado: resultado),
    ];
  }
}
