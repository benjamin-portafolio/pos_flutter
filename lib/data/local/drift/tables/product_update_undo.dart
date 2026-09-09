import 'package:drift/drift.dart';

/// Copia transaccional para revertir una eliminación optimista rechazada.
/// No usa CommonFields: es metadata local temporal, no una proyección de negocio.
/// Se descarta al confirmar el evento o al restaurar la proyección.
class ProductUpdateUndo extends Table {
  /// Evento pendiente cuya aplicación modificó o eliminó estas filas.
  TextColumn get eventId => text()();

  /// Agregado para encontrar sus respaldos al recibir confirmaciones.
  TextColumn get productId => text()();

  /// Filas Drift originales (producto, variantes y recetas) serializadas como JSON.
  TextColumn get snapshotJson => text()();
  @override
  Set<Column> get primaryKey => {eventId};
}
