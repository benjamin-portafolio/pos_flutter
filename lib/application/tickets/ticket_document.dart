/// Datos del dibujo común, sin dependencia de ventas ni de persistencia.
class TicketDocument {
  TicketDocument({
    required this.title,
    required this.identifier,
    required this.date,
    this.dateLabel = 'Fecha',
    required this.currency,
    required List<List<String>> itemRows,
    required List<(String, String)> totals,
    List<String> details = const [],
    List<String>? summary,
    this.footer,
  }) : itemRows = List.unmodifiable(itemRows.map(List<String>.unmodifiable)),
       totals = List.unmodifiable(totals),
       details = List.unmodifiable(details),
       summary = summary == null ? null : List.unmodifiable(summary);

  final String title, identifier, date, dateLabel, currency;
  final List<String> details;
  final List<String>? summary;
  final List<List<String>> itemRows;
  final List<(String, String)> totals;
  final String? footer;
}
