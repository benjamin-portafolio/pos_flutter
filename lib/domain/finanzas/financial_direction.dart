/// Dirección de una categoría o registro financiero adicional: ingreso (`in`)
/// o gasto (`out`). Es explícita e inmutable desde el alta; la UI la deriva
/// del contexto del botón presionado. Solo modela estado de consulta, sin Drift.
enum FinancialDirection {
  income('in', 'Ingreso'),
  expense('out', 'Gasto');

  const FinancialDirection(this.code, this.label);

  /// Código persistido y usado en payloads: `in` / `out`.
  final String code;

  /// Etiqueta visible para la UI.
  final String label;

  static FinancialDirection fromCode(String code) {
    return FinancialDirection.values.firstWhere(
      (value) => value.code == code,
      orElse: () => throw const FormatException(
        'direction debe ser in u out.',
      ),
    );
  }
}