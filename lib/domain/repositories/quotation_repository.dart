import '../cotizaciones/quotation.dart';
import '../cotizaciones/quotation_estimate.dart';

/// Lecturas limitadas al usuario/dispositivo local configurados.
abstract interface class QuotationRepository {
  /// Emite también cuando cambia el catálogo usado para estimar el documento.
  Stream<List<Quotation>> watchQuotations({bool onlyRecoverable = true});
  Stream<Quotation?> watchById(String quotationId);

  /// Cálculo en memoria; una única transacción de lectura, sin eventos.
  Future<QuotationEstimate> estimate(Quotation quotation);
  Future<Quotation?> findById(String quotationId);
}
