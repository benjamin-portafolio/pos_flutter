import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/nombre_variante.dart';

void main() {
  test('cumple los vectores compartidos de nombre y referencia', () async {
    final vectors = (jsonDecode(
          await File(
            'test/fixtures/product_variant_name_vectors.json',
          ).readAsString(),
        )
        as List).cast<Map<String, Object?>>();

    for (final vector in vectors) {
      final name = NombreVariante.fromInput(vector['input'] as String?);
      expect(name.value, vector['name']);
      expect(name.nameKey, vector['name_key']);
      final key = name.nameKey;
      final suffix = key == null
          ? null
          : base64Url.encode(utf8.encode(key)).replaceAll('=', '');
      expect(suffix, vector['ref_suffix']);
    }
  });

  test('mide el máximo en puntos de código', () {
    expect(NombreVariante.fromInput('😀' * 160).value?.runes.length, 160);
    expect(
      () => NombreVariante.fromInput('😀' * 161),
      throwsArgumentError,
    );
  });
}
