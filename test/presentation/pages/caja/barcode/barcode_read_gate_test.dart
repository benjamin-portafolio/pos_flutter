import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_gate.dart';

void main() {
  late Duration now;
  late BarcodeReadGate gate;
  setUp(() {
    now = Duration.zero;
    gate = BarcodeReadGate(clock: () => now)..setCameraActive(true);
  });

  test(
    '20 segundos de observaciones positivas: una presentación y una admisión',
    () {
      expect(gate.observe({'A'}), 'A');
      for (var i = 1; i <= 100; i++) {
        now = Duration(milliseconds: i * 200);
        expect(gate.observe({'A'}), isNull);
      }
    },
  );

  test('tres presentaciones con silencio; no necesita capturas vacías', () {
    for (var i = 0; i < 3; i++) {
      expect(gate.observe({'A'}), 'A');
      now += const Duration(milliseconds: 200);
      expect(gate.observe({'A'}), isNull);
      now += const Duration(milliseconds: 1100);
    }
  });

  test('A → B → A admite tres presentaciones incluso antes del umbral', () {
    for (final code in ['A', 'B', 'A']) {
      expect(gate.observe({code}), code);
      now += const Duration(milliseconds: 200);
    }
  });

  test('variaciones cortas de observación no rearman; el límite sí', () {
    expect(gate.observe({'A'}), 'A');
    now += const Duration(milliseconds: 999);
    expect(gate.observe({'A'}), isNull);
    now += const Duration(seconds: 1);
    expect(gate.observe({'A'}), 'A');
  });

  test('guardado lento observa la etiqueta: no simula retirada', () {
    expect(gate.observe({'A'}), 'A');
    for (var i = 1; i <= 100; i++) {
      now = Duration(milliseconds: i * 200);
      expect(gate.observe({'A'}, admissionEnabled: false), isNull);
    }
    now += const Duration(milliseconds: 200);
    expect(gate.observe({'A'}), isNull);
  });

  test(
    'otra presentación durante guardado se admite solo al observarla libre',
    () {
      expect(gate.observe({'A'}), 'A');
      now += const Duration(milliseconds: 200);
      expect(gate.observe({'B'}, admissionEnabled: false), isNull);
      now += const Duration(milliseconds: 200);
      expect(gate.observe({'B'}), 'B');
      expect(gate.observe({'B'}), isNull);
    },
  );

  test('no encola una presentación que desaparece durante el guardado', () {
    expect(gate.observe({'A'}), 'A');
    expect(gate.observe({'B'}, admissionEnabled: false), isNull);
    expect(gate.observe({'C'}, admissionEnabled: false), isNull);
    expect(gate.observe({'C'}), 'C');
    expect(gate.observe({'C'}), isNull);
  });

  test(
    'diálogo/ruta/segundo plano: pausa y primera observación no rearman',
    () {
      expect(gate.observe({'A'}), 'A');
      now += const Duration(milliseconds: 900);
      gate.setCameraActive(false);
      now += const Duration(minutes: 1);
      expect(gate.observe({'B'}), isNull);
      gate.setCameraActive(true);
      // Incluso si el primer frame tarda, no inferir retirada durante la pausa.
      now += const Duration(seconds: 5);
      expect(gate.observe({'A'}), isNull);
      now += const Duration(milliseconds: 200);
      expect(gate.observe({'A'}), isNull);
      now += const Duration(milliseconds: 1100);
      expect(gate.observe({'A'}), 'A');
    },
  );

  test('otro código al reanudar sí delimita una nueva presentación', () {
    expect(gate.observe({'A'}), 'A');
    gate.setCameraActive(false);
    now += const Duration(minutes: 1);
    gate.setCameraActive(true);
    expect(gate.observe({'B'}), 'B');
    expect(gate.observe({'A'}), 'A');
  });

  test(
    'ambigüedad no elige por orden ni rearma una etiqueta que sigue visible',
    () {
      expect(gate.observe({'A', 'B'}), isNull);
      expect(gate.observe({'A'}), 'A');
      for (var i = 1; i <= 20; i++) {
        now = Duration(milliseconds: i * 200);
        expect(gate.observe({'B', 'A'}), isNull);
      }
      expect(gate.observe({'A'}), isNull);
    },
  );

  test('un intento consumido sigue consumido aunque falle o se cancele', () {
    expect(gate.observe({'A'}), 'A');
    // La compuerta consume antes de ejecutar: no hay reset por resultado.
    expect(gate.observe({'A'}), isNull);
    expect(gate.observe({'A'}, admissionEnabled: false), isNull);
    expect(gate.observe({'A'}), isNull);
  });
}
