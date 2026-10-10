import 'package:flutter/material.dart';

import '../../../application/commands/cotizaciones/cotizacion_command_service.dart';
import '../../../application/commands/cotizaciones/recuperar_cotizacion_result.dart';
import '../../../core/di/injection.dart';
import '../../../domain/cotizaciones/quotation.dart';
import '../../../domain/repositories/quotation_repository.dart';
import 'models/quotation_display.dart';
import 'quotation_estimate_builder.dart';
import 'quotation_detail_screen.dart';

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({this.repository, this.commands, super.key});
  final QuotationRepository? repository;
  final CotizacionCommandService? commands;

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  late final _repository = widget.repository ?? getIt<QuotationRepository>();
  late Stream<List<Quotation>> _documents = _repository.watchQuotations();
  bool _onlyRecoverable = true;
  bool _opening = false;
  int _subscription = 0;

  void _reload({bool? onlyRecoverable}) => setState(() {
    _onlyRecoverable = onlyRecoverable ?? _onlyRecoverable;
    _documents = _repository.watchQuotations(onlyRecoverable: _onlyRecoverable);
    _subscription++;
  });

  Future<void> _open(Quotation quotation) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final result = await Navigator.of(context)
          .push<RecuperarCotizacionResult>(
            MaterialPageRoute(
              builder: (_) => QuotationDetailScreen(
                quotationId: quotation.id,
                repository: _repository,
                commands: widget.commands,
              ),
            ),
          );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (result != null) Navigator.of(context).pop(result);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cotizaciones')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Recuperables'),
                selected: _onlyRecoverable,
                onSelected: _opening
                    ? null
                    : (_) => _reload(onlyRecoverable: true),
              ),
              ChoiceChip(
                label: const Text('Todas'),
                selected: !_onlyRecoverable,
                onSelected: _opening
                    ? null
                    : (_) => _reload(onlyRecoverable: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Quotation>>(
            key: ValueKey(_subscription),
            stream: _documents,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No se pudieron cargar las cotizaciones.'),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final documents = snapshot.data!;
              if (documents.isEmpty) {
                return Center(
                  child: Text(
                    _onlyRecoverable
                        ? 'No hay cotizaciones recuperables.'
                        : 'No hay cotizaciones guardadas.',
                  ),
                );
              }
              return ListView.builder(
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final quotation = documents[index];
                  return QuotationEstimateBuilder(
                    key: ValueKey('estimate:${quotation.id}'),
                    quotation: quotation,
                    repository: _repository,
                    builder: (estimate) {
                      final display = QuotationDisplay(quotation, estimate);
                      return ListTile(
                        key: ValueKey(quotation.id),
                        title: Text('Cotización ${quotation.id}'),
                        subtitle: Text(
                          'Creada: ${display.date}\nTotal estimado actual: ${display.total} · ${display.status}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _opening ? null : () => _open(quotation),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
