enum _PeriodUnit { day, week, month, year, custom }

/// Período del selector de informes, con ambos días incluidos en hora local.
class ReportPeriod {
  const ReportPeriod._(this.start, this.end, this._unit);

  factory ReportPeriod.day(DateTime date) {
    final day = _dateOnly(date);
    return ReportPeriod._(day, day, _PeriodUnit.day);
  }

  factory ReportPeriod.week(DateTime date) {
    final day = _dateOnly(date);
    final start = DateTime(day.year, day.month, day.day - day.weekday + 1);
    return ReportPeriod._(
      start,
      DateTime(start.year, start.month, start.day + 6),
      _PeriodUnit.week,
    );
  }

  factory ReportPeriod.month(DateTime date) => ReportPeriod._(
    DateTime(date.year, date.month),
    DateTime(date.year, date.month + 1, 0),
    _PeriodUnit.month,
  );

  factory ReportPeriod.year(DateTime date) => ReportPeriod._(
    DateTime(date.year),
    DateTime(date.year, 12, 31),
    _PeriodUnit.year,
  );

  factory ReportPeriod.range(DateTime start, DateTime end) {
    final first = _dateOnly(start);
    final last = _dateOnly(end);
    if (last.isBefore(first)) {
      throw ArgumentError(
        'La fecha final debe ser igual o posterior al inicio.',
      );
    }
    return ReportPeriod._(first, last, _PeriodUnit.custom);
  }

  final DateTime start;
  final DateTime end;
  final _PeriodUnit _unit;

  DateTime get endExclusive => DateTime(end.year, end.month, end.day + 1);

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(endExclusive);

  ReportPeriod shift(int direction) => switch (_unit) {
    _PeriodUnit.day => ReportPeriod.day(
      DateTime(start.year, start.month, start.day + direction),
    ),
    _PeriodUnit.week => ReportPeriod.week(
      DateTime(start.year, start.month, start.day + 7 * direction),
    ),
    _PeriodUnit.month => ReportPeriod.month(
      DateTime(start.year, start.month + direction),
    ),
    _PeriodUnit.year => ReportPeriod.year(DateTime(start.year + direction)),
    _PeriodUnit.custom => _shiftRange(direction),
  };

  ReportPeriod _shiftRange(int direction) {
    // Cuenta días de calendario, sin asumir que un día local dura 24 horas.
    final days =
        DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
        1;
    return ReportPeriod.range(
      DateTime(start.year, start.month, start.day + days * direction),
      DateTime(end.year, end.month, end.day + days * direction),
    );
  }

  String get label => start == end
      ? formatDate(start)
      : '${formatDate(start)} – ${formatDate(end)}';

  static const monthNames = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String formatDate(DateTime date) =>
      '${date.day} ${monthNames[date.month - 1]} ${date.year}';

  static DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
