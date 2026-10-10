import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

/// Identidades v4 deterministas a partir de una intención aleatoria estable.
class QuotationRecoveryIdentity {
  static String saleItem(String saleId, String quotationItemId) =>
      _id(['quotation-recovery', saleId, quotationItemId]);
  static String draftEvent(
    String linkEventId,
    String saleId,
    String quotationItemId,
  ) => _id(['quotation-recovery-event', linkEventId, saleId, quotationItemId]);
  static String _id(List<String> seed) => const Uuid().v4(
    config: V4Options(
      sha256.convert(utf8.encode(jsonEncode(seed))).bytes.take(16).toList(),
      null,
    ),
  );
}
