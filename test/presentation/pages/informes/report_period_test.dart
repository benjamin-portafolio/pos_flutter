import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';

void main() {
  test('incluye ambos días completos y excluye los límites externos', () {
    final period = ReportPeriod.range(
      DateTime(2026, 9, 12),
      DateTime(2026, 9, 17),
    );
    expect(period.contains(DateTime(2026, 9, 11, 23, 59, 59)), isFalse);
    expect(period.contains(DateTime(2026, 9, 12)), isTrue);
    expect(period.contains(DateTime(2026, 9, 17, 23, 59, 59, 999)), isTrue);
    expect(period.contains(DateTime(2026, 9, 18)), isFalse);
    expect(period.contains(DateTime(2026, 9, 17, 12).toUtc()), isTrue);
    expect(
      () => ReportPeriod.range(DateTime(2026, 9, 17), DateTime(2026, 9, 12)),
      throwsArgumentError,
    );
  });

  test('semanas de lunes a domingo, incluso al cruzar de año', () {
    for (final day in [DateTime(2025, 12, 29), DateTime(2026, 1, 4)]) {
      final period = ReportPeriod.week(day);
      expect(period.start, DateTime(2025, 12, 29));
      expect(period.end, DateTime(2026, 1, 4));
      expect(period.shift(1).start, DateTime(2026, 1, 5));
      expect(period.shift(-1).end, DateTime(2025, 12, 28));
    }
  });

  test('avanza meses completos con diferentes longitudes y años bisiestos', () {
    final january = ReportPeriod.month(DateTime(2024, 1, 31));
    final february = january.shift(1);
    expect(february.start, DateTime(2024, 2));
    expect(february.end, DateTime(2024, 2, 29));
    expect(february.shift(1).end, DateTime(2024, 3, 31));
    expect(january.shift(-1).start, DateTime(2023, 12));
    expect(ReportPeriod.month(DateTime(2025, 2)).end, DateTime(2025, 2, 28));
    final year = ReportPeriod.year(DateTime(2024, 7, 10));
    expect(year.start, DateTime(2024));
    expect(year.end, DateTime(2024, 12, 31));
    expect(year.shift(-1).start, DateTime(2023));
    expect(year.shift(1).end, DateTime(2025, 12, 31));
  });

  test(
    'rango personalizado conserva días de calendario y permite ida y vuelta',
    () {
      final period = ReportPeriod.range(
        DateTime(2026, 9, 12),
        DateTime(2026, 9, 17),
      );
      expect(period.shift(-1).start, DateTime(2026, 9, 6));
      expect(period.shift(-1).end, DateTime(2026, 9, 11));
      expect(period.shift(1).start, DateTime(2026, 9, 18));
      expect(period.shift(1).end, DateTime(2026, 9, 23));
      expect(period.shift(1).shift(-1).label, period.label);
      // Estas fechas cruzan transiciones de horario en zonas que aún las usan.
      for (final month in [3, 11]) {
        final range = ReportPeriod.range(
          DateTime(2024, month, 1),
          DateTime(2024, month, 15),
        );
        expect(range.shift(1).start, DateTime(2024, month, 16));
        expect(range.shift(1).end, DateTime(2024, month, 30));
      }
      expect(
        ReportPeriod.day(DateTime(2024, 2, 29, 14)).shift(1).start,
        DateTime(2024, 3, 1),
      );
    },
  );
}
