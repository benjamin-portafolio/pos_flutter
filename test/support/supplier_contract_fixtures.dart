import 'dart:convert';
import 'dart:io';

/// Lee copias independientes de los fixtures canónicos compartibles con TS.
Map<String, Object?> supplierFixture(String name) => Map<String, Object?>.from(
  jsonDecode(File('test/fixtures/suppliers_v1/$name.json').readAsStringSync())
      as Map,
);
