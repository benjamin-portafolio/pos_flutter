import 'report_period.dart';

/// Agrupaciones de lectura del reporte, siempre en hora local.
enum SalesTimeGrouping {
  hour('Cada hora'),
  weekday('Día de la semana'),
  month('Mensual');

  const SalesTimeGrouping(this.label);
  final String label;

  int key(DateTime date) {
    final local = date.toLocal();
    return switch (this) {
      hour => local.hour,
      weekday => local.weekday,
      month => local.year * 12 + local.month - 1,
    };
  }

  String bucketLabel(int key) => switch (this) {
    hour =>
      '${key.toString().padLeft(2, '0')}:00 – '
          '${((key + 1) % 24).toString().padLeft(2, '0')}:00',
    weekday => const [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ][key - 1],
    month => '${ReportPeriod.monthNames[key % 12]} ${key ~/ 12}',
  };
}
