import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_test_payload.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/application/tickets/ticket_document.dart';
import 'package:pos_flutter/data/printing/esc_pos_ticket_encoder.dart';
import 'package:pos_flutter/data/printing/thermal_ticket_band.dart';
import 'package:pos_flutter/data/printing/thermal_ticket_renderer.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';

import '../../support/quotation_ui_fixtures.dart';
import '../../support/fake_printer_gateway.dart';
import '../../support/thermal_ticket_fixtures.dart';

Uint8List _raster(List<ThermalTicketBand> bands) =>
    Uint8List.fromList([for (final band in bands) ...band.raster]);

// Optional evidence export only. Production never accumulates this document's
// complete raster or persists a print job.
Future<void> _exportDocument(
  String directory,
  String name,
  TicketDocument document,
  PrinterProfile profile,
) async {
  final folder = await Directory(
    '$directory/../documentos',
  ).create(recursive: true);
  await File('${folder.path}/$name.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'evidenceType': 'synthetic_fixture_not_physical_print',
      'profile': {'address': profile.address, 'alias': profile.alias, 'paper': profile.paper.name, 'printableWidthDots': profile.printableWidthDots, 'imageCommand': profile.imageCommand.name, 'supportsCut': profile.supportsCut},
      'document': {
        'title': document.title,
        'identifier': document.identifier,
        'date': document.date,
        'dateLabel': document.dateLabel,
        'currency': document.currency,
        'details': document.details,
        'summary': document.summary,
        'itemRows': document.itemRows,
        'totals': [
          for (final total in document.totals) [total.$1, total.$2],
        ],
        'footer': document.footer,
      },
    })}\n',
  );
}

Future<Uint8List> _png(List<ThermalTicketBand> bands) async {
  final width = bands.first.width;
  final height = bands.fold(0, (sum, band) => sum + band.height);
  final raster = _raster(bands);
  final rgba = Uint8List(width * height * 4);
  for (var pixel = 0; pixel < width * height; pixel++) {
    final value = raster[pixel ~/ 8] & (0x80 >> (pixel % 8)) == 0 ? 255 : 0;
    rgba.setRange(pixel * 4, pixel * 4 + 4, [value, value, value, 255]);
  }
  final result = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    result.complete,
  );
  final image = await result.future;
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

// Independent wire decoder: consumes lengths, never scans command-like raster
// bytes. It checks every dot and detects extra feeds/initializations/rows.
List<ThermalTicketBand> _decode(
  List<List<int>> chunks,
  PrinterProfile profile,
) {
  expect(chunks.first.take(5), [27, 64, 27, 97, 0]);
  expect(chunks.last, [
    if (profile.imageCommand == PrinterImageCommand.escStar) ...[27, 50],
    27,
    100,
    3,
    if (profile.supportsCut) ...[29, 86, 0],
  ]);
  final bands = <ThermalTicketBand>[];
  for (var i = 0; i < chunks.length - 1; i++) {
    final chunk = chunks[i];
    var p = i == 0 ? 5 : 0;
    if (i == 0 && profile.imageCommand == PrinterImageCommand.escStar) {
      expect(chunk.sublist(p, p + 7), [29, 80, 0, 203, 27, 51, 24]);
      p += 7;
    }
    switch (profile.imageCommand) {
      case PrinterImageCommand.gsV0:
        expect(chunk.sublist(p, p + 4), [29, 118, 48, 0]);
        final width = (chunk[p + 4] + chunk[p + 5] * 256) * 8;
        final height = chunk[p + 6] + chunk[p + 7] * 256;
        final data = Uint8List.fromList(chunk.sublist(p + 8));
        expect(data.length, width ~/ 8 * height);
        bands.add(
          ThermalTicketBand(width: width, height: height, raster: data),
        );
      case PrinterImageCommand.gsL:
        expect(chunk.sublist(p, p + 3), [29, 40, 76]);
        final length = chunk[p + 3] + chunk[p + 4] * 256;
        expect(chunk.sublist(p + 5, p + 11), [48, 112, 48, 1, 1, 49]);
        final width = chunk[p + 11] + chunk[p + 12] * 256;
        final height = chunk[p + 13] + chunk[p + 14] * 256;
        final data = Uint8List.fromList(chunk.sublist(p + 15, p + 5 + length));
        expect(data.length, width ~/ 8 * height);
        expect(chunk.sublist(p + 5 + length), [29, 40, 76, 2, 0, 48, 50]);
        bands.add(
          ThermalTicketBand(width: width, height: height, raster: data),
        );
      case PrinterImageCommand.escStar:
        while (p < chunk.length) {
          expect(chunk.sublist(p, p + 3), [27, 42, 33]);
          final width = chunk[p + 3] + chunk[p + 4] * 256;
          p += 5;
          final data = Uint8List(width ~/ 8 * 24);
          for (var x = 0; x < width; x++) {
            for (var dy = 0; dy < 24; dy++) {
              if (chunk[p + x * 3 + dy ~/ 8] & (0x80 >> (dy % 8)) != 0) {
                data[dy * (width ~/ 8) + x ~/ 8] |= 0x80 >> (x % 8);
              }
            }
          }
          p += width * 3;
          expect(chunk[p++], 10);
          bands.add(ThermalTicketBand(width: width, height: 24, raster: data));
        }
    }
  }
  return bands;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontFile = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (await fontFile.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(fontFile.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  test(
    'production calibration A58 → B80 → A58 preserves command, raster and write backpressure',
    () async {
      final gateway = FakePrinterGateway();
      final service = TicketPrintService(
        gateway,
        encoder: const EscPosTicketEncoder(),
      );
      final a = thermalProfile(
        command: PrinterImageCommand.escStar,
        alias: 'A58 María Muñoz',
      );
      final b = thermalProfile(
        paper: PrinterPaper.mm80,
        command: PrinterImageCommand.gsL,
        address: 'AA:BB:CC:DD:EE:02',
      );
      try {
        for (final profile in [a, b, a]) {
          final offset = gateway.writes.length;
          gateway.pendingWrite = Completer<void>();
          final sending = service.printTest(profile);
          await Future.doWhile(() async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            return gateway.writes.length == offset;
          }).timeout(const Duration(seconds: 5));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(service.isBusy, isTrue);
          expect(gateway.writes.length, offset + 1);
          gateway.pendingWrite!.complete();
          expect((await sending).sent, isTrue);
          final chunks = gateway.writes.sublist(offset);
          final decoded = _raster(_decode(chunks, profile));
          final bands = await const ThermalTicketRenderer()
              .render(PrinterTestPayload.create(profile), profile)
              .toList();
          final expected = _raster(bands);
          expect(decoded.take(expected.length), expected);
          expect(decoded.skip(expected.length).every((p) => p == 0), isTrue);
          final directory = Platform.environment['POS_THERMAL_RENDER_DIR'];
          if (directory != null) {
            await Directory(directory).create(recursive: true);
            await _exportDocument(
              directory,
              'calibration-${profile.paper.name}',
              PrinterTestPayload.create(profile),
              profile,
            );
            await File(
              '$directory/calibration-${profile.paper.name}.png',
            ).writeAsBytes(await _png(bands));
          }
        }
        expect(gateway.calls.where((c) => c.startsWith('connect:')), [
          'connect:${a.address}',
          'connect:${b.address}',
          'connect:${a.address}',
        ]);
        expect(gateway.calls.where((c) => c == 'close'), hasLength(3));
      } finally {
        if (gateway.pendingWrite case final pending?) {
          if (!pending.isCompleted) pending.complete();
        }
        await service.dispose();
      }
    },
  );
  for (final paper in PrinterPaper.values) {
    test(
      'raster ${paper.name}: direct width, Spanish, measured amounts, payments and footer',
      () async {
        final profile = thermalProfile(paper: paper);
        final ticket = thermalDocument();
        final bands = await const ThermalTicketRenderer()
            .render(ticket, profile)
            .toList();
        expect(
          bands.every(
            (b) => b.width == profile.printableWidthDots && b.height <= 120,
          ),
          isTrue,
        );
        expect(bands.length, greaterThan(5));
        final pixels = _raster(bands);
        expect(pixels.any((p) => p != 0), isTrue);
        // White margins remain present in every raster line.
        final stride = profile.printableWidthDots ~/ 8;
        for (var y = 0; y < pixels.length ~/ stride; y++) {
          expect(pixels[y * stride], 0);
          expect(pixels[(y + 1) * stride - 1], 0);
        }
        final custom = thermalProfile(
          paper: paper,
          width: profile.printableWidthDots - 16,
        );
        expect(
          (await const ThermalTicketRenderer().render(ticket, custom).first)
              .width,
          custom.printableWidthDots,
        );
        final directory = Platform.environment['POS_THERMAL_RENDER_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          await _exportDocument(
            directory,
            'receipt-${paper.name}',
            ticket,
            profile,
          );
          await File(
            '$directory/receipt-${paper.name}.png',
          ).writeAsBytes(await _png(bands));
          final quotation = sampleQuotation();
          final estimate = sampleEstimate(quotation);
          await _exportDocument(
            directory,
            'quotation-${paper.name}',
            QuotationDisplay(quotation, estimate).ticket,
            profile,
          );
          final qbands = await const ThermalTicketRenderer()
              .render(QuotationDisplay(quotation, estimate).ticket, profile)
              .toList();
          await File(
            '$directory/quotation-${paper.name}.png',
          ).writeAsBytes(await _png(qbands));
        }
      },
    );
    test(
      '100 rows ${paper.name}: identical raster at different band boundaries; all methods retain order',
      () async {
        final document = thermalDocument(lines: 100);
        final profile = thermalProfile(paper: paper);
        final bands = await const ThermalTicketRenderer()
            .render(document, profile)
            .toList();
        final other = await const ThermalTicketRenderer(
          bandHeight: 96,
        ).render(document, profile).toList();
        final expected = _raster(bands);
        expect(_raster(other), expected);
        expect(bands.length, greaterThan(70));
        final short = await const ThermalTicketRenderer()
            .render(thermalDocument(lines: 99), profile)
            .toList();
        expect(expected.length, greaterThan(_raster(short).length));
        for (final command in PrinterImageCommand.values) {
          final captured = thermalProfile(paper: paper, command: command);
          final chunks = await const EscPosTicketEncoder()
              .encode(document, captured)
              .toList();
          expect(
            chunks.every(
              (b) => b.length <= profile.printableWidthDots ~/ 8 * 120 + 64,
            ),
            isTrue,
          );
          final decoded = _raster(_decode(chunks, captured));
          expect(decoded.take(expected.length), expected);
          expect(decoded.skip(expected.length).every((p) => p == 0), isTrue);
        }
        final directory = Platform.environment['POS_THERMAL_RENDER_DIR'];
        if (directory != null) {
          await _exportDocument(
            directory,
            'long-100-${paper.name}',
            document,
            profile,
          );
          await File(
            '$directory/long-100-${paper.name}.png',
          ).writeAsBytes(await _png(bands));
          await File(
            '$directory/long-100-end-${paper.name}.png',
          ).writeAsBytes(await _png(bands.sublist(bands.length - 8)));
        }
      },
    );
  }
  test(
    'known asymmetric bits convert from raster to 24-dot columns without flipping',
    () {
      final raster = Uint8List(16 ~/ 8 * 25);
      raster[0] = 0x80;
      raster[3] = 1;
      raster[48] = 0x40;
      final band = ThermalTicketBand(width: 16, height: 25, raster: raster);
      final bytes = EscPosTicketEncoder.encodeBand(
        band,
        PrinterImageCommand.escStar,
      );
      expect(bytes.take(5), [27, 42, 33, 16, 0]);
      expect(bytes[5], 0x80);
      expect(bytes[5 + 15 * 3], 0x40);
      expect(bytes[54 + 5 + 3], 0x80); // row 24, x=1
    },
  );
  test(
    'cut is present only in an explicit capable profile; no extra ending commands',
    () async {
      for (final command in PrinterImageCommand.values) {
        for (final cut in [false, true]) {
          final profile = thermalProfile(command: command, cut: cut);
          final chunks = await const EscPosTicketEncoder()
              .encode(thermalDocument(lines: 0), profile)
              .toList();
          _decode(chunks, profile);
        }
      }
    },
  );
}
