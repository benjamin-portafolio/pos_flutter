import 'dart:convert';
import 'dart:io';

/// Raíz de los fixtures JSON compartidos del contrato de seguimiento de
/// existencias (espejo de `src/testing/variant-tracking-fixtures.ts` de
/// NestJS). Se puede redirigir con `POS_VARIANT_FIXTURES` si el repo de
/// análisis cambia de lugar; el origen de los archivos vive en Análisis, no en
/// este repo.
const String _defaultVariantTrackingFixturesRoot =
    '/Users/benjamin/Library/CloudStorage/GoogleDrive-benjamin94833@gmail.com/My Drive/Projects/POS/analisis /08 - Roadmap/Seguimiento de existencias/Fixtures';

String get variantTrackingFixturesRoot =>
    Platform.environment['POS_VARIANT_FIXTURES'] ??
    _defaultVariantTrackingFixturesRoot;

/// Lee y parsea un fixture JSON relativo a la raíz (p. ej.
/// `alta/alta-autogenerada-origen-valido.json`).
Map<String, Object?> readVariantTrackingFixture(String relativePath) {
  final file = File('$variantTrackingFixturesRoot/$relativePath');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}
