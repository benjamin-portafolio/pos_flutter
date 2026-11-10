import 'package:drift/drift.dart';

/// Control técnico local; no usa CommonFields porque no es negocio ni evento.
/// Nunca se exporta como fila de negocio ni contiene credenciales de binding.
class RecoveryLocalState extends Table {
  /// Singleton de la instalación; siempre 1.
  IntColumn get singleton =>
      integer().customConstraint('NOT NULL CHECK (singleton = 1)')();

  /// Revisión durable: cada escritura de datos incrementa dentro del mismo commit.
  IntColumn get dataRevision => integer().withDefault(const Constant(0))();

  /// Instalación acreditada por un bootstrap; null para instalaciones legadas.
  TextColumn get serverInstanceId => text().nullable()();

  /// Generación acreditada; no se genera al capturar un origen legado.
  TextColumn get generationId => text().nullable()();

  /// Dataset del bootstrap, cuando existe.
  TextColumn get datasetId => text().nullable()();
  @override
  Set<Column> get primaryKey => {singleton};
}
