import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/articulos/sale_mode.dart';
import '../drift/app_database.dart';
import 'articulo_catalog_csv.dart';
import 'catalogo_pdf_documento.dart';

/// Compone el catálogo del dispositivo como PDF para compartir con el cliente.
///
/// Es una presentación, no un contrato: no participa del round-trip y no
/// comparte columnas con el CSV más allá de leer el mismo catálogo (D8). Lee la
/// misma consulta del listado, así que solo trae productos activos (H13), y sin
/// fotos a propósito: no existe columna de imagen en ningún repo (H6).
///
/// El trabajo se parte en dos: [documento] decide qué se muestra y en qué
/// orden, y [bytes] lo dibuja. Así lo que decide se puede probar sin leer un
/// binario.
abstract final class ArticuloCatalogPdf {
  /// Encabezado de los productos que no tienen categoría. La app ya llama
  /// "Sin categoría" a ese grupo, así que el PDF no inventa otro nombre.
  static const categoriaSinNombre = 'Sin categoría';

  /// Aviso obligatorio del pie: un catálogo impreso vive más que la lista de
  /// precios del día en que se generó.
  static const avisoPrecios = 'Precios sujetos a cambio.';

  static const _avisoCatalogoVacio =
      'No hay artículos que mostrar con los filtros aplicados.';
  static const _anchoPrecio = 92.0;
  static const _ladoQr = 34.0;

  /// Datos del PDF: categorías con encabezado, artículos en orden alfabético y
  /// una línea por variante con su precio, su unidad y su código de barras.
  static CatalogoPdfDocumento documento(
    List<ProductoListadoRow> rows, {
    required String negocio,
    required DateTime generado,
    String? telefono,
  }) {
    return CatalogoPdfDocumento(
      negocio: negocio,
      telefono: telefono,
      generado: generado,
      categorias: _categorias(rows),
    );
  }

  /// Dibuja el documento. Un catálogo sin filas dice que está vacío en vez de
  /// dejar una página en blanco que parece un fallo.
  static Future<Uint8List> bytes(CatalogoPdfDocumento documento) async {
    final pdf = pw.Document(
      title: '${documento.negocio} · Catálogo',
      author: documento.negocio,
      creator: documento.negocio,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        footer: (context) => _pie(documento, context),
        build: (context) => [
          _portada(documento),
          if (documento.categorias.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Text(
                _avisoCatalogoVacio,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
          for (final categoria in documento.categorias)
            ..._categoria(categoria),
        ],
      ),
    );

    return pdf.save();
  }

  /// Monto con el símbolo de moneda y separador de miles: `$1,500.00`. Es el
  /// mismo formato que usan los demás comprobantes de la app, para que el
  /// cliente lea los precios igual en todos lados.
  static String importe(int minor) {
    final negativo = minor < 0;
    final magnitud = minor.abs();
    final centavos = (magnitud % 100).toString().padLeft(2, '0');
    final pesos = (magnitud ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negativo ? '-' : ''}\$$pesos.$centavos';
  }

  /// Fecha local comprensible: `30/09/2026`.
  static String fecha(DateTime value) {
    final local = value.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(local.day)}/${pad(local.month)}/${local.year}';
  }

  /// Agrupa por categoría, con "Sin categoría" al final, y ordena artículos y
  /// categorías por nombre. El criterio de orden es la misma normalización que
  /// usa `name_key` en el resto del dominio, para que dos artículos con
  /// acentos y sin acentos se ordenen juntos.
  static List<CatalogoPdfCategoria> _categorias(List<ProductoListadoRow> rows) {
    final porProducto = <String, List<ProductoListadoRow>>{};
    for (final row in ArticuloCatalogCsv.filasExportables(rows)) {
      porProducto
          .putIfAbsent(row.producto.id, () => <ProductoListadoRow>[])
          .add(row);
    }

    final porCategoria = <String, List<CatalogoPdfArticulo>>{};
    for (final grupo in porProducto.values) {
      final varianteOrdenada = [...grupo]
        ..sort((left, right) {
          final porOrden = left.variante!.sortOrder.compareTo(
            right.variante!.sortOrder,
          );
          if (porOrden != 0) return porOrden;
          return left.variante!.id.compareTo(right.variante!.id);
        });
      final nombre = varianteOrdenada.first.producto.name;
      final categoria =
          varianteOrdenada.first.categoria?.name ?? categoriaSinNombre;
      porCategoria
          .putIfAbsent(categoria, () => <CatalogoPdfArticulo>[])
          .add(
            CatalogoPdfArticulo(
              nombre: nombre,
              lineas: varianteOrdenada.map(_linea).toList(growable: false),
            ),
          );
    }

    final conNombre = <CatalogoPdfCategoria>[];
    final sinNombre = <CatalogoPdfCategoria>[];
    porCategoria.forEach((nombre, articulos) {
      articulos.sort((a, b) {
        final porClave = _clave(a.nombre).compareTo(_clave(b.nombre));
        if (porClave != 0) return porClave;
        return a.nombre.compareTo(b.nombre);
      });
      final categoria = CatalogoPdfCategoria(
        nombre: nombre,
        articulos: List.unmodifiable(articulos),
      );
      if (nombre == categoriaSinNombre) {
        sinNombre.add(categoria);
      } else {
        conNombre.add(categoria);
      }
    });

    conNombre.sort((a, b) => _clave(a.nombre).compareTo(_clave(b.nombre)));
    return List.unmodifiable([...conNombre, ...sinNombre]);
  }

  static CatalogoPdfLinea _linea(ProductoListadoRow row) {
    final variante = row.variante!;
    final codigoBarras = variante.barcode?.trim();
    return CatalogoPdfLinea(
      nombreVariante: _vacioANulo(variante.name),
      codigoBarras: _vacioANulo(codigoBarras),
      precioVentaMinor: variante.salePriceMinor,
      etiquetaUnidad: _etiquetaUnidad(row),
    );
  }

  /// La unidad del precio siempre viaja. Venta por unidad es "por unidad" y
  /// venta por fracción es "por kg", "por g", "por ml" o "por l".
  static String _etiquetaUnidad(ProductoListadoRow row) {
    if (SaleMode.fromCode(row.producto.saleMode) != SaleMode.measured) {
      return 'por unidad';
    }
    final code = row.unidadVenta?.code.trim();
    if (code == null || code.isEmpty) return 'por unidad de venta';
    return 'por $code';
  }

  /// Criterio de orden alfabético. No usa `intl` a propósito: el plan cierra la
  /// fase con una única dependencia nueva y colar un ordenador de locale sería
  /// abrir otra decisión.
  static String _clave(String nombre) => unorm.nfkc(nombre).toLowerCase();

  static String? _vacioANulo(String? valor) {
    if (valor == null) return null;
    final trimmed = valor.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static pw.Widget _portada(CatalogoPdfDocumento documento) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            documento.negocio,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Catálogo de productos · ${documento.articulos} artículos · '
            '${fecha(documento.generado)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(height: 14, color: PdfColors.grey400),
        ],
      ),
    );
  }

  static List<pw.Widget> _categoria(CatalogoPdfCategoria categoria) {
    return [
      pw.Header(
        level: 0,
        text: categoria.nombre,
        textStyle: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      for (final articulo in categoria.articulos) ..._articulo(articulo),
      pw.SizedBox(height: 10),
    ];
  }

  static List<pw.Widget> _articulo(CatalogoPdfArticulo articulo) {
    return [
      for (var i = 0; i < articulo.lineas.length; i++)
        _lineaVisual(articulo, i),
      pw.Divider(height: 10, color: PdfColors.grey300),
    ];
  }

  /// Una línea por variante. El nombre del producto solo va en la primera: en
  /// las siguientes lo que identifica la línea es el nombre de la variante.
  static pw.Widget _lineaVisual(CatalogoPdfArticulo articulo, int indice) {
    final linea = articulo.lineas[indice];
    final descripcion = <pw.Widget>[
      if (indice == 0)
        pw.Text(
          articulo.nombre,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      if (linea.nombreVariante != null)
        pw.Text(
          linea.nombreVariante!,
          style: pw.TextStyle(
            fontSize: indice == 0 ? 9.5 : 11,
            color: PdfColors.grey800,
          ),
        ),
      if (linea.tieneCodigoBarras)
        pw.Text(
          linea.codigoBarras!,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: descripcion,
            ),
          ),
          pw.SizedBox(
            width: _anchoPrecio,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  importe(linea.precioVentaMinor),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  linea.etiquetaUnidad,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          if (linea.tieneCodigoBarras) ...[
            pw.SizedBox(width: 8),
            _qr(linea.codigoBarras!),
          ],
        ],
      ),
    );
  }

  /// QR generado desde el código de barras de la variante. Sin código de barras
  /// no hay QR: un QR con otro contenido sería un dato que el catálogo no tiene.
  static pw.Widget _qr(String codigoBarras) {
    return pw.SizedBox(
      width: _ladoQr,
      height: _ladoQr,
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(
          errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
        ),
        data: codigoBarras,
        drawText: false,
      ),
    );
  }

  /// Pie de todas las páginas: de qué negocio es el catálogo, cuándo se generó,
  /// el aviso de precios y el contacto, más la numeración.
  static pw.Widget _pie(CatalogoPdfDocumento documento, pw.Context context) {
    final contacto = documento.telefono == null
        ? avisoPrecios
        : '$avisoPrecios · Tel. ${documento.telefono}';
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  documento.negocio,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '${fecha(documento.generado)} · $contacto',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
