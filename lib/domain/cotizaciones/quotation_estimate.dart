import 'quotation_line_estimate.dart';

/// Estimación coherente del catálogo SQLite conocido por esta instalación.
class QuotationEstimate {
  QuotationEstimate({
    required this.calculatedAt,
    required this.totalMinor,
    required List<QuotationLineEstimate> lines,
  }) : lines = List.unmodifiable(lines);
  final DateTime calculatedAt;
  final String currency = 'MXN';
  final int? totalMinor;
  final List<QuotationLineEstimate> lines;
}
