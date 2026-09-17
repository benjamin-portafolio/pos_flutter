import 'package:flutter/material.dart';

import 'models/report_period.dart';
import 'widgets/report_range_calendar.dart';

class ReportDateFilterScreen extends StatefulWidget {
  const ReportDateFilterScreen({
    super.key,
    required this.initialPeriod,
    required this.today,
  });

  final ReportPeriod initialPeriod;
  final DateTime today;

  @override
  State<ReportDateFilterScreen> createState() => _ReportDateFilterScreenState();
}

class _ReportDateFilterScreenState extends State<ReportDateFilterScreen> {
  late ReportPeriod _period = widget.initialPeriod;
  bool _selectingEnd = false;

  void _selectDate(DateTime date) => setState(() {
    if (!_selectingEnd) {
      _period = ReportPeriod.range(date, date);
      _selectingEnd = true;
    } else {
      _period = date.isBefore(_period.start)
          ? ReportPeriod.range(date, _period.start)
          : ReportPeriod.range(_period.start, date);
      _selectingEnd = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    final shortcuts = [
      ('Hoy', ReportPeriod.day(today)),
      ('Ayer', ReportPeriod.day(today).shift(-1)),
      ('Esta semana', ReportPeriod.week(today)),
      ('La semana pasada', ReportPeriod.week(today).shift(-1)),
      ('Este mes', ReportPeriod.month(today)),
      ('El mes pasado', ReportPeriod.month(today).shift(-1)),
      ('Este año', ReportPeriod.year(today)),
      ('El año pasado', ReportPeriod.year(today).shift(-1)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtrar por fecha'),
        leading: IconButton(
          tooltip: 'Cancelar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _selectingEnd
                          ? 'Selecciona la fecha final'
                          : 'Selecciona la fecha inicial',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Para consultar un solo día, selecciónalo dos veces.',
                      textAlign: TextAlign.center,
                    ),
                    ReportRangeCalendar(
                      period: _period,
                      selectingEnd: _selectingEnd,
                      onDateSelected: _selectDate,
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < shortcuts.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var j = i; j < i + 2; j++) ...[
                              if (j != i) const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(context, shortcuts[j].$2),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 52),
                                    padding: const EdgeInsets.all(12),
                                  ),
                                  child: Text(
                                    shortcuts[j].$1,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _selectingEnd
                  ? 'Inicio: ${ReportPeriod.formatDate(_period.start)} · Selecciona el final'
                  : 'Período seleccionado: ${_period.label}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _selectingEnd
                  ? null
                  : () => Navigator.pop(context, _period),
              child: const Text('Mostrar informes'),
            ),
          ],
        ),
      ),
    );
  }
}
