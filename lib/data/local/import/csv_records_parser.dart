/// Parser CSV de texto: conserva todos los campos como String y procesa
/// registros completos, incluidos saltos de línea dentro de comillas.
class CsvRecordsParser {
  const CsvRecordsParser();

  List<List<String>> parse(
    String text, {
    required String separator,
    int? maxRecords,
  }) {
    if (separator != ',' && separator != ';') {
      throw ArgumentError.value(separator, 'separator');
    }
    final records = <List<String>>[];
    var fields = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var closed = false;
    var started = false;
    var recordStarted = false;

    void finishField() {
      fields.add(field.toString());
      field = StringBuffer();
      closed = false;
      started = false;
    }

    void finishRecord() {
      finishField();
      // Solo las líneas realmente vacías se omiten; "" y ; son datos.
      if (recordStarted ||
          fields.length > 1 ||
          fields.single.trim().isNotEmpty) {
        records.add(fields);
      }
      fields = <String>[];
      recordStarted = false;
    }

    for (var i = text.startsWith('\uFEFF') ? 1 : 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(char);
        }
      } else if (char == separator) {
        recordStarted = true;
        finishField();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        finishRecord();
        if (maxRecords != null && records.length >= maxRecords) return records;
      } else if (char == '"' && !started && !closed) {
        quoted = true;
        started = true;
        recordStarted = true;
      } else {
        if (closed || char == '"') {
          throw const FormatException('Comillas CSV inválidas.');
        }
        started = true;
        field.write(char);
      }
    }
    if (quoted) {
      throw const FormatException('Campo CSV con comillas sin cerrar.');
    }
    finishRecord();
    return records;
  }
}
