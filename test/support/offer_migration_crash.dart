import 'dart:io';
import 'package:pos_flutter/data/local/drift/offer_pricing_schema.dart';

/// Proceso hijo de prueba: termina después de ALTER y antes del COMMIT.
Future<void> main(List<String> args) => prepareAppDatabase(
  File(args.single),
  afterAlterForTesting: (_) => exit(73),
);
