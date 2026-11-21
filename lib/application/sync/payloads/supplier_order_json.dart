import '../../../domain/ventas/measured_sale_calculator.dart';
import 'dart:convert';

const supplierOrderMaxItems = 50;
const supplierOrderMaxPayloadBytes = 81920;
const supplierOrderMaxInteger = 9007199254740991;
Map<String, Object?> orderRecord(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Objeto requerido');
  }
  return value;
}

int orderInt(Object? value, [int min = 0]) {
  if (value is! int || value < min || value > supplierOrderMaxInteger) {
    throw const FormatException('Entero fuera de rango');
  }
  return value;
}

String orderText(Object? value, int max) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.runes.length > max ||
      value != value.trim()) {
    throw const FormatException('Texto fuera de rango');
  }
  return value;
}

String orderUuid(Object? value) {
  final s = orderText(value, 36);
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(s)) {
    throw const FormatException('UUID v4 requerido');
  }
  return s;
}

List<T> orderLines<T>(
  Object? value,
  T Function(Object?) parse,
  String Function(T) key,
) {
  if (value is! List || value.isEmpty || value.length > supplierOrderMaxItems) {
    throw const FormatException('Se requieren 1..50 partidas');
  }
  final result = value.map(parse).toList(growable: false);
  if (result.map(key).toSet().length != result.length) {
    throw const FormatException('Identidad duplicada');
  }
  return List.unmodifiable(result);
}

void orderPayloadSize(Map<String, Object?> json) {
  if (utf8.encode(jsonEncode(json)).length > supplierOrderMaxPayloadBytes) {
    throw const FormatException('Payload excede 80 KiB');
  }
}

int orderAmount(int price, int quantity, int reference) {
  orderInt(price);
  orderInt(quantity, 1);
  orderInt(reference, 1);
  return price == 0
      ? 0
      : const MeasuredSaleCalculator().totalMinor(
          unitPriceMinor: price,
          quantityAtomic: quantity,
          priceReferenceQuantityAtomic: reference,
        );
}

int? orderTotal(Iterable<int?> values) {
  if (values.any((v) => v == null)) return null;
  final sum = values.fold(BigInt.zero, (a, b) => a + BigInt.from(b!));
  if (sum > BigInt.from(supplierOrderMaxInteger)) {
    throw const FormatException('Total fuera de rango');
  }
  return sum.toInt();
}
