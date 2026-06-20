import 'package:flutter/material.dart';

class LabeledUnderlineField extends StatelessWidget {
  const LabeledUnderlineField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        hintText: hint,
        border: const UnderlineInputBorder(),
      ),
    );
  }
}
