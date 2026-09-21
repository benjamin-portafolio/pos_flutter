import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Proyección de clientes creada por eventos locales o recibidos del servidor.
@DataClassName('ClienteRow')
class Clientes extends Table with CommonFields {
  @override
  Set<Column> get primaryKey => {id};

  /// Nombre obligatorio del cliente, sin espacios al inicio ni al final.
  TextColumn get nombre =>
      text().customConstraint("NOT NULL CHECK (length(trim(nombre)) > 0)")();

  /// Teléfono opcional como texto para conservar prefijos y ceros iniciales.
  TextColumn get telefono => text().nullable()();
}
