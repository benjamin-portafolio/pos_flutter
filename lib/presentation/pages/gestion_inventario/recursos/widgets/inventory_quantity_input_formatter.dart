import 'package:flutter/services.dart';

class InventoryQuantityInputFormatter extends TextInputFormatter {
  InventoryQuantityInputFormatter(this.maxFractionDigits);

  final int maxFractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pattern = maxFractionDigits == 0
        ? RegExp(r'^\d*$')
        : RegExp('^\\d*(?:[.,]\\d{0,$maxFractionDigits})?\$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
