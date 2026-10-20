import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_measurement.dart';
import 'package:pos_flutter/data/weighing/rhino_bar8rs_protocol.dart';

void main() {
  late RhinoBar8RsProtocol parser;
  setUp(() => parser = RhinoBar8RsProtocol());

  test(
    'replays physically captured bytes, retaining exact weight and unit',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/weighing/rhino_bar8rs_2026_10_20.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final row in fixture['observed'] as List) {
        final hex = row['hex'] as String;
        final reading = parser.add([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]).single;
        expect(reading.weight!.grams, row['grams']);
        expect(reading.weight!.decimalPlaces, 3);
        expect(reading.stability, ScaleStability.unknown);
        expect(reading.isValid, row['grams'] > 0);
      }
      expect(RhinoBar8RsProtocol.weightRequest, [0x50]);
    },
  );

  test(
    'every possible split waits for CR; concatenated frames stay ordered',
    () {
      final frame = ascii.encode('  0.278 kg\r');
      for (var split = 0; split < frame.length; split++) {
        parser.reset();
        expect(parser.add(frame.sublist(0, split)), isEmpty);
        expect(parser.add(frame.sublist(split)).single.weight!.grams, 278);
      }
      final readings = parser.add(ascii.encode('  0.278 kg\r  0.000 kg\r'));
      expect(readings.map((r) => r.weight!.grams), [278, 0]);
      expect(readings.last.failure, ScaleFailure.nonPositive);
    },
  );

  test('fragmentation down to individual bytes and optional LF after CR', () {
    final readings = <ScaleMeasurement>[];
    for (final byte in ascii.encode('  0.278 kg\r\n  0.400 kg\r\n')) {
      readings.addAll(parser.add([byte]));
    }
    expect(readings.map((r) => r.weight!.grams), [278, 400]);
  });

  test(
    'oversized noise is bounded, rejected immediately, suffix discarded',
    () {
      final readings = parser.add(List.filled(100000, 65));
      expect(readings.single.failure, ScaleFailure.invalidFrame);
      expect(parser.bufferedBytes, 0);
      expect(parser.add(ascii.encode('0.278 kg\r')), isEmpty);
      expect(parser.add(ascii.encode('0.278 kg\r')).single.weight!.grams, 278);
    },
  );

  test('binary noise cannot be silently stripped into a positive weight', () {
    final readings = parser.add([0xFF, ...ascii.encode('0.278 kg\r')]);
    expect(readings.single.failure, ScaleFailure.invalidFrame);
    expect(parser.bufferedBytes, 0);
  });

  for (final text in [
    'OL',
    'ERROR',
    'ST,0.278 kg',
    '0.278',
    '0,278 kg',
    'NaN kg',
    'noise 0.278 kg',
    '0.278 kg trailing',
    '',
  ]) {
    test('synthetic unknown format is invalid: "$text"', () {
      expect(
        parser.add(ascii.encode('$text\r')).single.failure,
        ScaleFailure.invalidFrame,
      );
    });
  }
  for (final unit in ['lb', 'g', 'KG']) {
    test('unverified unit $unit is never guessed as kg', () {
      expect(
        parser.add(ascii.encode('0.278 $unit\r')).single.failure,
        ScaleFailure.unsupportedUnit,
      );
    });
  }
  test('synthetic signed, zero and subgram weights cannot be accepted', () {
    expect(
      parser.add(ascii.encode('-0.278 kg\r')).single.failure,
      ScaleFailure.nonPositive,
    );
    expect(
      parser.add(ascii.encode('0.000 kg\r')).single.failure,
      ScaleFailure.nonPositive,
    );
    expect(
      parser.add(ascii.encode('0.0004 kg\r')).single.failure,
      ScaleFailure.unrepresentableWeight,
    );
    expect(parser.add(ascii.encode('0.2780 kg\r')).single.weight!.grams, 278);
  });
  test('overflow is rejected using integer arithmetic before conversion', () {
    expect(
      parser.add(ascii.encode('9007199254740.991 kg\r')).single.weight!.grams,
      9007199254740991,
    );
    expect(
      parser.add(ascii.encode('9007199254740.992 kg\r')).single.failure,
      ScaleFailure.overflow,
    );
  });
  test('reset discards partial data between sessions', () {
    parser.add(ascii.encode('0.'));
    parser.reset();
    expect(parser.add(ascii.encode('278 kg\r')).single.isValid, isFalse);
  });
}
