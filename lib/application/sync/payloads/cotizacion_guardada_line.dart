import 'package:uuid/uuid.dart';

import 'quotation_selection_snapshot.dart';
import 'quotation_json.dart';

/// Identidades propias y selección de una línea emitida.
class CotizacionGuardadaLine {
  CotizacionGuardadaLine({
    required String id,
    required String sourceSaleItemId,
    required this.sortOrder,
    required this.selection,
  }) : id = id.trim(),
       sourceSaleItemId = sourceSaleItemId.trim() {
    if (this.id.isEmpty ||
        this.sourceSaleItemId.isEmpty ||
        this.id == this.sourceSaleItemId ||
        sortOrder < 0 ||
        sortOrder > QuotationJson.maxInteger) {
      throw const FormatException('Línea de cotización inválida.');
    }
  }

  final String id, sourceSaleItemId;
  final int sortOrder;
  final QuotationSelectionSnapshot selection;

  /// La identidad depende sólo de la intención y de la línea origen.
  static String idFor(String quotationId, String sourceSaleItemId) =>
      const Uuid().v5(
        Namespace.url.value,
        'quotation:$quotationId:item:$sourceSaleItemId',
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'source_sale_item_id': sourceSaleItemId,
    'sort_order': sortOrder,
    'selection': selection.toJson(),
  };

  factory CotizacionGuardadaLine.fromJson(Map<String, Object?> json) {
    QuotationJson.keys(json, {
      'id',
      'source_sale_item_id',
      'sort_order',
      'selection',
    });
    final selection = json['selection'];
    if (json['id'] is! String ||
        json['source_sale_item_id'] is! String ||
        json['sort_order'] is! int ||
        selection is! Map<String, Object?>) {
      throw const FormatException('Línea de cotización inválida.');
    }
    return CotizacionGuardadaLine(
      id: json['id']! as String,
      sourceSaleItemId: json['source_sale_item_id']! as String,
      sortOrder: json['sort_order']! as int,
      selection: QuotationSelectionSnapshot.fromJson(selection),
    );
  }
}
