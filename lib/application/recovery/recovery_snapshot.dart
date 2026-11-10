import 'dart:io';

/// Vista inmutable de una captura preservada. Diagnóstico/exportación solo usan
/// esta vista. rows recorre PK en orden estable, sin cargar la tabla completa.
abstract interface class RecoverySnapshot {
  File get file;
  Map<String, Object?> get cut;
  List<String> get tables;
  List<String> get oversizedTables;
  List<String> get duplicateOfficialSequences;
  List<String> get exportEntities;
  Iterable<Map<String, Object?>> exportRows(String entity);
  int count(String table);
  Iterable<Map<String, Object?>> rows(String table);
  Iterable<Map<String, Object?>> relatedRows(
    String table,
    String column,
    String value,
  );
  Map<String, Object?>? event(String id);
  Map<String, Object?>? rowByKey(String table, String column, String value);
  List<Map<String, Object?>> get foreignKeyViolations;
  void close();
}
