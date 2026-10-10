import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../application/export/articulo_catalog_export_service.dart';
import '../../../../application/import/articulo_catalog_import_service.dart';
import '../../../../application/import/articulo_import_batch_service.dart';
import '../../../../application/import/articulo_import_progreso.dart';
import 'bulk_import_progress.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../../../domain/repositories/unidad_inventario_repository.dart';

/// Archivo elegido por el usuario, ya leído.
///
/// La lectura ocurre en el adaptador de plataforma, no en la pantalla: así la
/// pantalla no depende del sistema de archivos y se puede probar inyectando el
/// contenido.
typedef ArchivoCargaMasiva = ({String nombre, String contenido});

/// Pantalla de carga masiva desde un archivo CSV (D11).
///
/// Revisa el archivo y pide confirmación antes de ejecutar lotes de alta.
class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({
    required this.categoriaRepository,
    required this.productoRepository,
    required this.unidadInventarioRepository,
    this.exportService,
    this.importService,
    this.batchService,
    this.pickFile,
    this.shareFile,
    super.key,
  });

  final CategoriaRepository categoriaRepository;
  final ProductoRepository productoRepository;
  final UnidadInventarioRepository unidadInventarioRepository;

  /// Null lo resuelve el contenedor de dependencias.
  final ArticuloCatalogExportService? exportService;
  final ArticuloCatalogImportService? importService;
  final ArticuloImportBatchService? batchService;

  /// Inyectable para las pruebas; en producción abre el selector de archivos y
  /// lee lo elegido. Null significa cancelación.
  final Future<ArchivoCargaMasiva?> Function()? pickFile;

  /// Inyectable para las pruebas; en producción delega en `share_plus`.
  final Future<ShareResult> Function(ShareParams)? shareFile;

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  /// Qué está pasando ahora. El enum evita el `bool` que no dice si lo que se
  /// está generando es la plantilla o el reporte.
  _Paso? _paso;
  final _scroll = ScrollController();
  String? _archivoNombre;
  ArticuloImportReporte? _reporte;
  String? _contenido;
  ArticuloImportProgreso? _progreso;

  /// Interruptor de importar solo las válidas. El archivo con problemas no se
  /// importa entero: se muestra el reporte y se pregunta.
  bool _soloValidas = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _paso == null,
      child: Scaffold(
        key: const Key('bulk_import_screen'),
        appBar: AppBar(title: const Text('CARGA MASIVA')),
        body: SafeArea(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_progreso != null) ...[
                BulkImportProgress(progreso: _progreso!),
                const SizedBox(height: 16),
              ],
              const Text(
                'Descarga la plantilla, pega los datos de tus artículos y elige '
                'el archivo para revisarlo antes de darlo de alta. En esta '
                'versión solo se dan de alta artículos nuevos: para cambiar uno '
                'existente, edítalo en su pantalla.',
                key: Key('bulk_import_intro'),
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('download_template_button'),
                onPressed: _paso == null ? _descargarPlantilla : null,
                icon: _icono(_Paso.plantilla, Icons.description_outlined),
                label: const Text('Descargar plantilla'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('pick_bulk_import_file_button'),
                onPressed: _paso == null ? _elegirArchivo : null,
                icon: _icono(_Paso.archivo, Icons.folder_open),
                label: const Text('Elegir archivo CSV'),
              ),
              if (_archivoNombre != null) ...[
                const SizedBox(height: 12),
                Text(
                  _archivoNombre!,
                  key: const Key('bulk_import_file_name'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              // El reporte va antes que las reglas: es la respuesta a la acción
              // que el usuario acaba de hacer, y las reglas se leen una vez.
              if (_reporte != null) ...[
                const SizedBox(height: 16),
                _Reporte(
                  reporte: _reporte!,
                  soloValidas: _soloValidas,
                  onSoloValidasChanged: _paso == null && _progreso == null
                      ? (valor) => setState(() => _soloValidas = valor)
                      : null,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('confirm_bulk_import_button'),
                  onPressed: _puedeImportar ? _confirmarImportacion : null,
                  icon: _icono(_Paso.importacion, Icons.upload_file),
                  label: const Text('Importar artículos'),
                ),
              ],
              const SizedBox(height: 24),
              _ReglasDelArchivo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icono(_Paso paso, IconData icono) {
    if (_paso != paso) return Icon(icono);
    return const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _descargarPlantilla() async {
    setState(() => _paso = _Paso.plantilla);
    try {
      final servicio =
          widget.exportService ?? getIt<ArticuloCatalogExportService>();
      final archivo = await servicio.exportarPlantilla();
      await _compartir(archivo.ruta);
      if (!mounted) return;
      _avisar('Se descargó la plantilla del catálogo.');
    } catch (_) {
      if (!mounted) return;
      _avisar('No se pudo descargar la plantilla. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _paso = null);
    }
  }

  /// El catálogo se lee una vez y se pasa ya resuelto al servicio de
  /// validación, que no toca la base (H18: la lista es un `Stream` y aquí se
  /// quiere una foto, no una suscripción).
  Future<void> _elegirArchivo() async {
    setState(() => _paso = _Paso.archivo);
    try {
      final elegido = await (widget.pickFile ?? _seleccionarArchivo)();
      if (elegido == null) return;
      final reporte = await _validar(elegido.contenido);
      if (!mounted) return;
      setState(() {
        _reporte = reporte;
        _archivoNombre = elegido.nombre;
        _contenido = elegido.contenido;
        _progreso = null;
      });
    } catch (_) {
      if (!mounted) return;
      _avisar('No se pudo leer el archivo. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _paso = null);
    }
  }

  bool get _puedeImportar =>
      _paso == null &&
      _progreso == null &&
      _reporte != null &&
      _reporte!.importable &&
      _reporte!.productos.isNotEmpty &&
      (!_reporte!.hayErrores || _soloValidas);

  Future<void> _confirmarImportacion() async {
    if (!_puedeImportar) return;
    setState(() => _paso = _Paso.confirmacion);
    try {
      // Releer el catálogo evita usar una revisión anterior a otra carga.
      final reporte = await _validar(_contenido!);
      if (!mounted) return;
      setState(() => _reporte = reporte);
      if (!reporte.importable ||
          reporte.productos.isEmpty ||
          (reporte.hayErrores && !_soloValidas)) {
        return;
      }
      final cantidad = reporte.productos.length;
      final lotes =
          (cantidad + ArticuloImportBatchService.productosPorLote - 1) ~/
          ArticuloImportBatchService.productosPorLote;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar carga masiva'),
          content: Text(
            'Se darán de alta $cantidad artículos (${reporte.filasValidas} filas) '
            'en $lotes lotes. Cada lote se guarda completo; si falla, se revierte '
            'y los demás continúan.'
            '${reporte.hayErrores ? '\nLas filas con problemas se omitirán.' : ''}',
          ),
          actions: [
            TextButton(
              key: const Key('cancel_bulk_import_dialog'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('accept_bulk_import_dialog'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar importación'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
      setState(() => _paso = _Paso.importacion);
      final servicio =
          widget.batchService ?? getIt<ArticuloImportBatchService>();
      await servicio.importar(
        reporte.productos,
        onProgress: (progreso) {
          if (!mounted) return;
          final primerAvance = _progreso == null;
          setState(() => _progreso = progreso);
          if (primerAvance && _scroll.hasClients) _scroll.jumpTo(0);
        },
      );
    } catch (_) {
      if (mounted) {
        _avisar(
          'No se pudo completar la carga. Revisa el archivo antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _paso = null);
    }
  }

  Future<ArticuloImportReporte> _validar(String contenido) async {
    final servicio =
        widget.importService ?? getIt<ArticuloCatalogImportService>();
    final categorias = await widget.categoriaRepository.obtenerCategorias();
    final unidades = await widget.unidadInventarioRepository
        .obtenerUnidadesActivas();
    final articulos = await widget.productoRepository.watchArticulos().first;
    return servicio.validar(
      contenido,
      catalogo: ArticuloImportCatalogo(
        categorias: categorias
            .map(
              (categoria) => ArticuloImportCategoria(
                id: categoria.id,
                nombre: categoria.nombre,
              ),
            )
            .toList(growable: false),
        unidades: unidades,
        nombresArticulos: {for (final articulo in articulos) articulo.nombre},
      ),
    );
  }

  /// Adaptador de plataforma: abre el selector, lee lo elegido y devuelve su
  /// nombre y su texto. Cancelar devuelve null y nada más; un archivo que no se
  /// puede leer deja volar el error, que la pantalla traduce a un aviso.
  Future<ArchivoCargaMasiva?> _seleccionarArchivo() async {
    final resultado = await FilePicker.pickFiles(
      dialogTitle: 'Elegir archivo del catálogo',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final ruta = resultado?.paths.single;
    if (ruta == null) return null;
    final contenido = await File(ruta).readAsString();
    return (nombre: ruta.split(RegExp(r'[/\\]')).last, contenido: contenido);
  }

  Future<void> _compartir(String ruta) async {
    final box = context.findRenderObject() as RenderBox?;
    final origen = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await (widget.shareFile ?? SharePlus.instance.share)(
      ShareParams(
        files: [XFile(ruta)],
        fileNameOverrides: [ruta.split(RegExp(r'[/\\]')).last],
        title: 'Plantilla del catálogo',
        sharePositionOrigin: origen,
        downloadFallbackEnabled: false,
      ),
    );
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }
}

enum _Paso { plantilla, archivo, confirmacion, importacion }

/// Las reglas que el archivo tiene que cumplir, en la pantalla.
///
/// No todos van a abrir `catalogo_columnas.csv`, así que lo esencial va aquí.
class _ReglasDelArchivo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('bulk_import_rules'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reglas del archivo',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '• Es la plantilla que descargas, con las 10 columnas en el mismo '
              'orden y separadas por comas (",").\n'
              '• Reemplaza o elimina las filas de ejemplo antes de cargar el '
              'archivo.\n'
              '• El nombre del artículo agrupa sus variantes y no puede '
              'repetirse ni existir ya.\n'
              '• Si un artículo tiene más de una variante, todas necesitan '
              'nombre.\n'
              '• Venta por fracción: solo g, kg, ml o l.\n'
              '• Con seguimiento de existencias la columna "existencias" es '
              'obligatoria, y 0 es válido.\n'
              '• La categoría se busca por nombre y debe existir: no se crean '
              'al importar.\n'
              '• Máximo 500 filas por archivo.',
              style: TextStyle(height: 1.5, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reporte del archivo: cuántas filas se pueden dar de alta y, si hay
/// problemas, la lista con línea, columna y motivo.
///
/// El interruptor de importar solo las válidas vive aquí porque el archivo con
/// problemas no se importa entero: se muestra el reporte y se pregunta.
class _Reporte extends StatelessWidget {
  const _Reporte({
    required this.reporte,
    required this.soloValidas,
    required this.onSoloValidasChanged,
  });

  final ArticuloImportReporte reporte;
  final bool soloValidas;
  final ValueChanged<bool>? onSoloValidasChanged;

  @override
  Widget build(BuildContext context) {
    final filas = reporte.filasValidas;
    final productos = reporte.productos.length;
    return Card(
      key: const Key('bulk_import_report'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revisión del archivo',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '$productos artículos y $filas filas listos para dar de alta.',
              key: const Key('bulk_import_valid_count'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (!reporte.importable)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Mientras haya un error de encabezado no se puede importar '
                  'nada. Descarga la plantilla y vuelve a pegar los datos.',
                  key: Key('bulk_import_blocked'),
                  style: TextStyle(height: 1.4),
                ),
              ),
            if (reporte.hayErrores) ...[
              const SizedBox(height: 12),
              Text(
                '${reporte.errores.length} '
                '${reporte.errores.length == 1 ? 'problema' : 'problemas'}:',
                key: const Key('bulk_import_error_count'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('import_only_valid_switch'),
                value: soloValidas,
                onChanged: reporte.importable ? onSoloValidasChanged : null,
                title: const Text('Importar solo las filas válidas'),
                subtitle: Text(
                  reporte.importable
                      ? 'Las filas con problemas se omiten.'
                      : 'No disponible mientras el encabezado no coincida.',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 4),
              ...reporte.errores.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${error.descripcion}: ${error.motivo}',
                    key: ValueKey<String>(
                      'bulk_import_error_${error.linea}_${error.columna}',
                    ),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
