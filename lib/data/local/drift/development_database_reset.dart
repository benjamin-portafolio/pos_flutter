import 'dart:io';
import 'offer_pricing_schema.dart';

/// API conservada para consumidores anteriores. Ya no elimina datos persistentes.
Future<bool> resetDevelopmentDatabase(
  File file, {
  required Future<bool> Function() shouldPreserveRestoredDatabase,
}) async {
  await prepareAppDatabase(file);
  return false;
}
