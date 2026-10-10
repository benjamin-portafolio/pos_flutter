import 'supplier_json.dart';

/// Datos del catálogo; la identidad y trazabilidad pertenecen al sobre.
class ProveedorCreadoPayload {
  ProveedorCreadoPayload({required String name, String? phone, String? notes})
    : name = SupplierJson.requiredText(name, 'name'),
      phone = SupplierJson.optionalText(phone, 'phone'),
      notes = SupplierJson.optionalText(notes, 'notes');

  static const aggregateType = 'supplier';
  static const eventType = 'proveedor_creado';
  final String name;
  final String? phone;
  final String? notes;

  factory ProveedorCreadoPayload.fromJson(Map<String, Object?> json) =>
      ProveedorCreadoPayload(
        name: SupplierJson.requiredText(json['name'], 'name'),
        phone: SupplierJson.optionalText(json['phone'], 'phone'),
        notes: SupplierJson.optionalText(json['notes'], 'notes'),
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'phone': phone,
    'notes': notes,
  };
}
