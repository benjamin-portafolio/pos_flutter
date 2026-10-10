import 'dart:convert';
import 'dart:io';

Map<String, Object?> quotationFixture(String name) =>
    (jsonDecode(
              File('test/fixtures/quotation_v2/$name.json').readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();
Map<String, Object?> copyQuotationJson(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
