import 'dart:convert';
import 'dart:io';

/// Raíz de los fixtures JSON compartidos del contrato de ingresos/gastos
/// (espejo de `src/testing/financial-fixtures.ts` de NestJS). Se puede
/// redirigir con `POS_FINANCIAL_FIXTURES` si el repo de análisis cambia de
/// lugar; el origen de los archivos vive en Análisis, no en este repo.
const String _defaultFinancialFixturesRoot =
    '/Users/benjamin/Library/CloudStorage/GoogleDrive-benjamin94833@gmail.com/My Drive/Projects/POS/analisis /08 - Roadmap/Ingresos y gastos por sesiones/Fixtures';

String get financialFixturesRoot =>
    Platform.environment['POS_FINANCIAL_FIXTURES'] ??
    _defaultFinancialFixturesRoot;

/// Lee y parsea un fixture JSON relativo a la raíz (p. ej.
/// `registro/entry-renta-cash-valid.json`).
Map<String, Object?> readFinancialFixture(String relativePath) {
  final file = File('$financialFixturesRoot/$relativePath');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}