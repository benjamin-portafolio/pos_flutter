import 'package:flutter/material.dart';

import '../models/report_period.dart';

/// Calendario de rango: cada pulsación se comunica al selector del período.
class ReportRangeCalendar extends StatefulWidget {
  const ReportRangeCalendar({
    super.key,
    required this.period,
    required this.selectingEnd,
    required this.onDateSelected,
  });

  final ReportPeriod period;
  final bool selectingEnd;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<ReportRangeCalendar> createState() => _ReportRangeCalendarState();
}

class _ReportRangeCalendarState extends State<ReportRangeCalendar> {
  late DateTime _month = DateTime(
    widget.period.start.year,
    widget.period.start.month,
  );

  @override
  void didUpdateWidget(ReportRangeCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.start != widget.period.start) {
      _month = DateTime(widget.period.start.year, widget.period.start.month);
    }
  }

  void _moveMonth(int offset) => setState(() {
    _month = DateTime(_month.year, _month.month + offset);
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final offset = _month.weekday - DateTime.monday;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = (offset + days + 6) ~/ 7;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Mes anterior',
              onPressed: () => _moveMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${ReportPeriod.monthNames[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Mes siguiente',
              onPressed: () => _moveMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _day(row * 7 + column - offset + 1, days, colors),
                ),
            ],
          ),
      ],
    );
  }

  Widget _day(int day, int days, ColorScheme colors) {
    if (day < 1 || day > days) return const SizedBox(height: 48);
    final date = DateTime(_month.year, _month.month, day);
    final selected = widget.period.contains(date);
    final endpoint = date == widget.period.start || date == widget.period.end;
    final background = endpoint
        ? colors.primary
        : selected
        ? colors.primaryContainer
        : Colors.transparent;
    final foreground = endpoint ? colors.onPrimary : colors.onSurface;
    return Semantics(
      selected: selected,
      label:
          '${widget.selectingEnd ? 'Fecha final' : 'Fecha inicial'}: '
          '${ReportPeriod.formatDate(date)}',
      excludeSemantics: true,
      button: true,
      onTap: () => widget.onDateSelected(date),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(endpoint ? 24 : 0),
        child: InkWell(
          key: ValueKey('calendar-${date.year}-${date.month}-${date.day}'),
          borderRadius: BorderRadius.circular(24),
          onTap: () => widget.onDateSelected(date),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Text('$day', style: TextStyle(color: foreground)),
            ),
          ),
        ),
      ),
    );
  }
}
