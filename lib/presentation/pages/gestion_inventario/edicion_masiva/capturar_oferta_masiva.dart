import 'package:flutter/material.dart';
import '../../../../application/edicion_masiva/cambio_explicito.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';

/// Cancelar conserva la intención anterior; vacío no significa retirar.
Future<CambioExplicito<String?>?> capturarOfertaMasiva(
  BuildContext context, {
  required int? actual,
  required CambioExplicito<String?> cambio,
}) => showDialog<CambioExplicito<String?>>(
  context: context,
  builder: (_) => _OfertaDialog(actual: actual, cambio: cambio),
);

class _OfertaDialog extends StatefulWidget {
  const _OfertaDialog({required this.actual, required this.cambio});
  final int? actual;
  final CambioExplicito<String?> cambio;
  @override
  State<_OfertaDialog> createState() => _OfertaDialogState();
}

class _OfertaDialogState extends State<_OfertaDialog> {
  final form = GlobalKey<FormState>();
  late String accion;
  late TextEditingController text;
  @override
  void initState() {
    super.initState();
    final cambio = widget.cambio;
    accion = !cambio.establecer
        ? 'conservar'
        : cambio.valor == null
        ? 'retirar'
        : 'establecer';
    text = TextEditingController(
      text: cambio.establecer
          ? cambio.valor ?? ''
          : widget.actual == null
          ? ''
          : const ImporteComercialCodec().format(widget.actual!),
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Precio de oferta'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: accion,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'conservar', child: Text('Conservar')),
              DropdownMenuItem(value: 'establecer', child: Text('Establecer')),
              DropdownMenuItem(value: 'retirar', child: Text('Retirar')),
            ],
            onChanged: (v) => setState(() => accion = v!),
          ),
          if (accion == 'establecer')
            TextFormField(
              key: const Key('bulk_offer_amount'),
              controller: text,
              decoration: const InputDecoration(labelText: 'Importe de oferta'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                try {
                  const ImporteComercialCodec().parse(
                    value ?? '',
                    admiteCero: false,
                  );
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
          if (accion == 'retirar')
            const Text('La variante quedará sin oferta.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            accion == 'conservar'
                ? const CambioExplicito<String?>.conservar()
                : CambioExplicito<String?>.establecer(
                    accion == 'retirar' ? null : text.text.trim(),
                  ),
          );
        },
        child: const Text('Aplicar'),
      ),
    ],
  );
}
