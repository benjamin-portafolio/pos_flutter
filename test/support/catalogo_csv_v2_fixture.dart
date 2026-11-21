import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/csv_records_parser.dart';

/// Archivo histórico v2 para verificar compatibilidad de lectura. La app ya no
/// lo ofrece como plantilla pública, pero sus operaciones siguen admitidas.
String catalogoCsvV2Fixture(List<ProductoListadoRow> rows) {
  final actuales = const CsvRecordsParser().parse(
    ArticuloCatalogCsv.catalogo(rows),
    separator: ',',
  );
  final porId = {for (final row in rows) row.variante?.id: row};
  String escapar(String v) =>
      v.contains(RegExp('[,"\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;
  return [
    ArticuloCsvContract.columnasReposicion.join(','),
    for (final c in actuales.skip(1))
      (() {
        final row = porId[c[1]]!;
        final v = row.variante!;
        return [
          ...c.take(8),
          c[9],
          c[10],
          c[11],
          c[13],
          c[8],
          '',
          '',
          '',
          '2',
          v.currentSupplierId ?? '',
          v.currentSupplierId == null ? 'retirar' : 'establecer',
          v.targetStockAtomic?.toString() ?? '',
          v.targetStockAtomic == null ? '' : row.unidadInventario?.unitId ?? '',
          v.targetStockAtomic == null ? 'retirar' : 'establecer',
        ].map(escapar).join(',');
      })(),
    '',
  ].join('\n');
}
