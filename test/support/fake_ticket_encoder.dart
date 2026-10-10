import 'dart:async';

import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/ticket_encoder.dart';
import 'package:pos_flutter/application/tickets/ticket_document.dart';

class FakeTicketEncoder implements TicketEncoder {
  final documents = <TicketDocument>[];
  final profiles = <PrinterProfile>[];
  Completer<void>? pending;
  Object? error;
  Stream<List<int>> Function()? source;

  @override
  Stream<List<int>> encode(
    TicketDocument document,
    PrinterProfile profile,
  ) async* {
    documents.add(document);
    profiles.add(profile);
    await pending?.future;
    if (error case final error?) throw error;
    if (source case final source?) {
      yield* source();
    } else {
      yield [27, 64, 1];
      yield [2];
      yield [27, 100, 3];
    }
  }
}
