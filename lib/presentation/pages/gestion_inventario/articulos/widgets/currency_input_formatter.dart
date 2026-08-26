import 'package:flutter/services.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final accepted = RegExp(r'^-?\d*(?:[.,]\d{0,2})?$');
    return accepted.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
