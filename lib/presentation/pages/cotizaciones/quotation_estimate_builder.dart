import 'package:flutter/material.dart';
import '../../../domain/cotizaciones/quotation.dart';
import '../../../domain/cotizaciones/quotation_estimate.dart';
import '../../../domain/repositories/quotation_repository.dart';

/// Conecta el documento durable con una estimación temporal de lectura.
class QuotationEstimateBuilder extends StatefulWidget {
  const QuotationEstimateBuilder({
    required this.quotation,
    required this.repository,
    required this.builder,
    super.key,
  });
  final Quotation quotation;
  final QuotationRepository repository;
  final Widget Function(QuotationEstimate) builder;
  @override
  State<QuotationEstimateBuilder> createState() =>
      _QuotationEstimateBuilderState();
}

class _QuotationEstimateBuilderState extends State<QuotationEstimateBuilder> {
  late Future<QuotationEstimate> _estimate = widget.repository.estimate(
    widget.quotation,
  );
  @override
  void didUpdateWidget(covariant QuotationEstimateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quotation != widget.quotation ||
        oldWidget.repository != widget.repository) {
      _estimate = widget.repository.estimate(widget.quotation);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<QuotationEstimate>(
    future: _estimate,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        // FutureBuilder conserva data/error del futuro anterior al cambiarlo.
        // No presentar una estimación anterior mientras se calcula la nueva.
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            _estimate = widget.repository.estimate(widget.quotation);
          }),
          child: const Text('No se pudo estimar. Reintentar'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.builder(snapshot.data!);
    },
  );
}
