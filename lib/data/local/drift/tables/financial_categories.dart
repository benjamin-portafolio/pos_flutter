import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Categorías financieras de ingresos/gastos adicionales, independientes de
/// las categorías de productos. Se crean vacías; el usuario las da de alta.
@DataClassName('FinancialCategoryRow')
class FinancialCategories extends Table with CommonFields {
  /// Nombre visible, normalizado NFKC+trim con 1..100 code points.
  /// No hay unicidad por nombre: dos categorías pueden tener el mismo texto.
  TextColumn get name => text().customConstraint(
    'NOT NULL CHECK(length(name) BETWEEN 1 AND 100)',
  )();

  /// Dirección inmutable desde el alta: 'in' (ingreso) u 'out' (gasto).
  /// La UI la deriva del contexto del botón presionado.
  TextColumn get direction => text().customConstraint(
    "NOT NULL CHECK(direction IN ('in', 'out'))",
  )();

  /// Naturaleza/clasificación inmutable desde el alta (5 valores); no se
  /// infiere del nombre. `operating` es el valor predeterminado operativo.
  TextColumn get nature => text().customConstraint(
    "NOT NULL CHECK(nature IN ('operating', 'capital', 'asset_purchase', 'inventory_purchase', 'financing'))",
  )();

  /// `active` (CommonFields) no es funcional en esta primera versión: es
  /// convención de proyección y permanece `true`; no representa borrado ni
  /// anulación (no hay edición/eliminación en esta entrega).
  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK(NOT (direction = 'in' AND nature IN ('asset_purchase', 'inventory_purchase')))",
  ];
}