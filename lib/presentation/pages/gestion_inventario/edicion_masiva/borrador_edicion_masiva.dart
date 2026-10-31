import '../../../../application/edicion_masiva/base_revision_masiva.dart';
import '../../../../application/edicion_masiva/cambio_explicito.dart';
import '../../../../application/edicion_masiva/cambio_variante_masiva.dart';
import '../../../../application/edicion_masiva/catalogo_edicion_masiva.dart';
import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../application/edicion_masiva/entrada_mercancia_masiva.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../domain/articulos/precio_venta.dart';
import '../../../../domain/articulos/proveedor_variante.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../application/edicion_masiva/operacion_edicion_masiva.dart';
import 'fila_edicion_form.dart';
import 'fila_revision_masiva.dart';
import 'revision_edicion_masiva.dart';

enum VistaEdicionMasiva { porTarea, recepcionCompacta }

enum TareaEdicionMasiva { oferta, venta, costoProveedor, agregarExistencias }

/// Único borrador de pantalla para ambas vistas; ninguna pulsación escribe.
class BorradorEdicionMasiva {
  BorradorEdicionMasiva({required this.catalogo, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final CatalogoEdicionMasiva catalogo;
  final DateTime Function() _ahora;
  static const _importes = ImporteComercialCodec();
  static const _cantidades = InventoryQuantityCodec();
  final _filas = <ClaveVariante, FilaEdicionForm>{};
  final _cargas = <ClaveVariante, Future<void>>{};
  final _bases = <String, BaseRevisionMasiva>{};
  String? _proveedorGlobal;

  String busqueda = '';
  bool soloCambios = false;
  VistaEdicionMasiva vista = VistaEdicionMasiva.porTarea;
  TareaEdicionMasiva tarea = TareaEdicionMasiva.venta;
  ClaveVariante? seleccion;

  Map<ClaveVariante, FilaEdicionForm> get filas => Map.unmodifiable(_filas);
  String? get proveedorGlobal => _proveedorGlobal;

  /// Validación de captura sin lecturas ni escrituras. La revisión final vuelve
  /// a leer las bases y la disponibilidad de proveedores de forma consistente.
  FilaRevisionMasiva revisarCaptura(ClaveVariante clave) {
    final fila = _filas[clave]!;
    return _normalizar(fila, fila.original, {
      if (fila.proveedorId != null) fila.proveedorId!,
    });
  }

  void elegirProveedorGlobal(String? id) => _proveedorGlobal = _proveedor(id);

  Future<List<FilaCatalogoMasivo>> buscar({
    int limite = 100,
    int desplazamiento = 0,
  }) => catalogo.buscar(
    busqueda: busqueda,
    limite: limite,
    desplazamiento: desplazamiento,
  );

  Future<void> editarVenta(ClaveVariante clave, String texto) async {
    await _asegurarFila(clave);
    _filas[clave] = _filas[clave]!.copiar(
      venta: CambioExplicito.establecer(texto),
    );
  }

  Future<void> editarOferta(
    ClaveVariante clave,
    CambioExplicito<String?> oferta,
  ) async {
    await _asegurarFila(clave);
    _filas[clave] = _filas[clave]!.copiar(oferta: oferta);
  }

  Future<void> editarCosto(ClaveVariante clave, String texto) async {
    final proveedorPredeterminado = _proveedorGlobal;
    final fechaCaptura = _ahora();
    await _asegurarFila(clave);
    final fila = _filas[clave]!;
    _filas[clave] = fila.copiar(
      costo: CambioExplicito.establecer(texto),
      proveedorCapturado: true,
      proveedorId: fila.proveedorCapturado
          ? const CambioExplicito.conservar()
          : CambioExplicito.establecer(proveedorPredeterminado),
      fechaInformada: fila.fechaInformada ?? fechaCaptura,
    );
  }

  /// Sustituye la entrada pendiente, incluso al pasar de una vista a otra.
  Future<void> editarCantidad(ClaveVariante clave, String texto) async {
    await _asegurarFila(clave);
    _filas[clave] = _filas[clave]!.copiar(
      cantidad: CambioExplicito.establecer(texto),
    );
  }

  /// Selección explícita de detalle. Usa el costo mostrado; desconocido exige captura.
  Future<void> editarProveedor(
    ClaveVariante clave,
    String? id, {
    DateTime? fecha,
  }) async {
    await _asegurarFila(clave);
    final fila = _filas[clave]!;
    _filas[clave] = fila.copiar(
      proveedorCapturado: true,
      proveedorId: CambioExplicito.establecer(_proveedor(id)),
      costo: CambioExplicito.establecer(
        fila.costo ??
            (fila.original.costoMinor == null
                ? ''
                : _importes.format(fila.original.costoMinor!)),
      ),
      fechaInformada: fecha ?? fila.fechaInformada ?? _ahora(),
    );
  }

  void retirarFila(ClaveVariante clave) {
    _filas.remove(clave);
    if (!_filas.keys.any((k) => k.productId == clave.productId)) {
      _bases.remove(clave.productId);
    }
    if (seleccion == clave) seleccion = null;
  }

  /// Reúne también las filas ocultas por búsqueda, filtro o vista.
  Future<RevisionEdicionMasiva> prepararRevision() async {
    await Future.wait(_cargas.values.toList());
    final capturas = _filas.values.toList();
    final lectura = await catalogo.leer(
      capturas.map((f) => f.original.clave).toSet(),
      proveedorIds: capturas
          .map((f) => f.proveedorId)
          .whereType<String>()
          .toSet(),
    );
    return RevisionEdicionMasiva(
      capturas.map(
        (f) => _normalizar(
          f,
          lectura.filas[f.original.clave],
          lectura.proveedoresActivos,
        ),
      ),
    );
  }

  Future<void> recuperar(Iterable<OperacionEdicionMasiva> operaciones) async {
    final cambios = operaciones.expand((op) => op.cambios).toList();
    final lectura = await catalogo.leer(cambios.map((c) => c.clave).toSet());
    final nuevas = <ClaveVariante, FilaEdicionForm>{};
    for (final cambio in cambios) {
      if (_filas.containsKey(cambio.clave)) continue;
      final actual = lectura.filas[cambio.clave];
      if (actual == null) {
        throw StateError(
          'Una variante pendiente dejó de estar disponible. Cierra esa captura desde recuperación.',
        );
      }
      final pareja = cambio.precioProveedor;
      final entrada = cambio.entrada;
      final original = FilaCatalogoMasivo(
        clave: actual.clave,
        baseProducto: cambio.baseProducto,
        nombreProducto: actual.nombreProducto,
        nombreVariante: actual.nombreVariante,
        ventaMinor: actual.ventaMinor,
        ofertaMinor: actual.ofertaMinor,
        costoMinor: actual.costoMinor,
        configuracionVenta: actual.configuracionVenta,
        unidadVenta: actual.unidadVenta,
        entrada: entrada?.base ?? actual.entrada,
        impedimentoEntrada: actual.impedimentoEntrada,
        proveedores: actual.proveedores,
      );
      nuevas[cambio.clave] = FilaEdicionForm(
        original: original,
        baseProducto: cambio.baseProducto,
        oferta: cambio.oferta.establecer
            ? CambioExplicito.establecer(
                cambio.oferta.valor == null
                    ? null
                    : _importes.format(cambio.oferta.valor!),
              )
            : const CambioExplicito.conservar(),
        venta: cambio.venta.establecer
            ? _importes.format(cambio.venta.valor)
            : null,
        costo: cambio.costo.establecer
            ? _importes.format(cambio.costo.valor)
            : pareja == null
            ? null
            : _importes.format(pareja.precioInformadoMenor),
        cantidad: entrada == null
            ? null
            : _cantidades.formatAtomic(
                entrada.cantidadAtomic,
                entrada.base.unidad,
              ),
        proveedorCapturado: cambio.costo.establecer || pareja != null,
        proveedorId: pareja?.proveedorId,
        fechaInformada: pareja == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                pareja.fechaInformadaMs,
                isUtc: true,
              ),
      );
    }
    _filas.addAll(nuevas);
    for (final fila in nuevas.values) {
      _bases[fila.original.clave.productId] = fila.baseProducto;
    }
  }

  /// Solo una acción explícita del usuario puede adoptar bases nuevas. Conserva
  /// todos los textos y exige otra revisión antes de ejecutar.
  Future<void> revisarEstadoNuevo() async {
    final lectura = await catalogo.leer(_filas.keys.toSet());
    final nuevas = <ClaveVariante, FilaEdicionForm>{};
    for (final fila in _filas.values) {
      final actual = lectura.filas[fila.original.clave];
      if (actual == null) {
        throw StateError(
          'Retira las variantes que dejaron de estar disponibles antes de revisar.',
        );
      }
      final anterior = fila.original;
      // Un vínculo o unidad distintos necesitan retirar/recapturar la entrada;
      // adoptar su cantidad como si fuera la misma unidad sería una conversión.
      if (fila.cantidad != null &&
          fila.cantidad!.trim().isNotEmpty &&
          anterior.entrada != null &&
          (actual.entrada == null ||
              anterior.entrada!.recurso.id != actual.entrada!.recurso.id ||
              anterior.entrada!.unidad != actual.entrada!.unidad)) {
        final vieja = anterior.entrada!.unidad;
        final nueva = actual.entrada?.unidad;
        if (actual.entrada == null ||
            anterior.entrada!.recurso.id != actual.entrada!.recurso.id ||
            vieja.id != nueva!.id ||
            vieja.dimension != nueva.dimension ||
            vieja.factorAtomico != nueva.factorAtomico ||
            vieja.maximosDecimales != nueva.maximosDecimales) {
          throw StateError(
            'El vínculo o la unidad cambió. Retira y recaptura esa entrada explícitamente.',
          );
        }
      }
      nuevas[actual.clave] = FilaEdicionForm(
        original: actual,
        baseProducto: actual.baseProducto,
        oferta: fila.oferta,
        venta: fila.venta,
        costo: fila.costo,
        cantidad: fila.cantidad,
        proveedorCapturado: fila.proveedorCapturado,
        proveedorId: fila.proveedorId,
        fechaInformada: fila.fechaInformada,
      );
    }
    _filas
      ..clear()
      ..addAll(nuevas);
    _bases
      ..clear()
      ..addAll({
        for (final f in nuevas.values)
          f.original.clave.productId: f.baseProducto,
      });
  }

  /// Filtrado sobre la revisión completa, sin cambiar las capturas originales.
  List<FilaRevisionMasiva> filasVisibles(RevisionEdicionMasiva revision) {
    final query = busqueda.trim().toLowerCase();
    return List.unmodifiable(
      revision.filas.where(
        (r) =>
            (!soloCambios || r.estado != EstadoFilaMasiva.sinCambios) &&
            (r.captura.original.nombreProducto.toLowerCase().contains(query) ||
                (r.captura.original.nombreVariante ?? '')
                    .toLowerCase()
                    .contains(query)),
      ),
    );
  }

  Future<void> _asegurarFila(ClaveVariante clave) async {
    if (_filas.containsKey(clave)) return;
    final carga = _cargas.putIfAbsent(clave, () => _cargar(clave));
    try {
      await carga;
    } finally {
      _cargas.remove(clave);
    }
  }

  Future<void> _cargar(ClaveVariante clave) async {
    final original = (await catalogo.leer({clave})).filas[clave];
    if (original == null) {
      throw StateError('El producto o la variante ya no están disponibles.');
    }
    final base = _bases.putIfAbsent(
      clave.productId,
      () => original.baseProducto,
    );
    _filas[clave] = FilaEdicionForm(original: original, baseProducto: base);
  }

  FilaRevisionMasiva _normalizar(
    FilaEdicionForm f,
    FilaCatalogoMasivo? actual,
    Set<String> proveedoresActivos,
  ) {
    final errores = <CampoEdicionMasiva, String>{};
    T? validar<T>(CampoEdicionMasiva campo, T Function() parse) {
      try {
        return parse();
      } on FormatException catch (e) {
        errores[campo] = e.message;
        return null;
      }
    }

    if (actual == null ||
        f.baseProducto.eventId == null ||
        !f.baseProducto.mismoEstado(actual.baseProducto)) {
      errores[CampoEdicionMasiva.base] =
          'El producto cambió o dejó de estar disponible. Revisa la captura.';
    }
    var venta = const CambioExplicito<int>.conservar();
    var costo = const CambioExplicito<int>.conservar();
    var oferta = const CambioExplicito<int?>.conservar();
    ProveedorVariante? proveedor;
    EntradaMercanciaMasiva? entrada;
    if (f.venta != null) {
      final value = validar(
        CampoEdicionMasiva.venta,
        () => _importes.parse(f.venta!, admiteCero: false),
      );
      if (value != null && value != f.original.ventaMinor) {
        venta = CambioExplicito.establecer(value);
      }
    }
    if (f.oferta.establecer) {
      final text = f.oferta.valor;
      if (text == null) {
        oferta = const CambioExplicito.establecer(null);
      } else {
        final value = validar(
          CampoEdicionMasiva.oferta,
          () => _importes.parse(text, admiteCero: false),
        );
        if (value != null) oferta = CambioExplicito.establecer(value);
      }
    }
    final offer = oferta.establecer ? oferta.valor : f.original.ofertaMinor;
    final normal = venta.establecer ? venta.valor : f.original.ventaMinor;
    if (offer != null && offer > normal) {
      errores[CampoEdicionMasiva.oferta] =
          'La oferta no puede superar el precio normal.';
    }
    if (f.costo != null) {
      final value = validar(
        CampoEdicionMasiva.costo,
        () => _importes.parse(f.costo!, admiteCero: true),
      );
      if (value != null) {
        if (value != f.original.costoMinor) {
          costo = CambioExplicito.establecer(value);
        }
        if (f.proveedorId != null) {
          final fecha = f.fechaInformada;
          if (fecha == null || fecha.millisecondsSinceEpoch < 1) {
            errores[CampoEdicionMasiva.fecha] =
                'La fecha informada debe ser posterior al inicio de Unix.';
          } else {
            final pareja = validar(
              CampoEdicionMasiva.proveedor,
              () => ProveedorVariante(
                proveedorId: f.proveedorId!,
                precioInformadoMenor: value,
                fechaInformadaMs: fecha.toUtc().millisecondsSinceEpoch,
              ),
            );
            if (pareja != null) {
              if (!proveedoresActivos.contains(pareja.proveedorId)) {
                errores[CampoEdicionMasiva.proveedor] =
                    'El proveedor no está disponible.';
              }
              // El contrato conserva la fecha anterior si no cambia el precio.
              if (!f.original.proveedores.any(
                (p) =>
                    p.proveedorId == pareja.proveedorId &&
                    p.precioInformadoMenor == value,
              )) {
                proveedor = pareja;
              }
            }
          }
        }
      }
    }
    final textoCantidad = f.cantidad?.trim() ?? '';
    if (textoCantidad.isNotEmpty) {
      final base = f.original.entrada;
      if (base == null) {
        if (!RegExp(r'^0+(?:[.,]0+)?$').hasMatch(textoCantidad)) {
          errores[CampoEdicionMasiva.cantidad] = f.original.impedimentoEntrada!;
        }
      } else {
        final cantidad = validar(
          CampoEdicionMasiva.cantidad,
          () => _cantidades.parseNonNegativeAtomic(textoCantidad, base.unidad),
        );
        if (cantidad != null && cantidad > 0) {
          final vigente = actual?.entrada;
          if (vigente == null || !base.mismoEstado(vigente)) {
            errores[CampoEdicionMasiva.base] =
                'El vínculo, unidad, recurso o saldo cambió. Revisa la entrada.';
          }
          final max = BigInt.from(PrecioVenta.maxUnidadMenor);
          if ((BigInt.from(base.existenciaAtomic) + BigInt.from(cantidad))
                      .abs() >
                  max ||
              (BigInt.from(base.disponibleAtomic) + BigInt.from(cantidad))
                      .abs() >
                  max) {
            errores[CampoEdicionMasiva.cantidad] =
                'El saldo previsto excede el límite permitido.';
          }
          entrada = EntradaMercanciaMasiva(
            base: base,
            cantidadAtomic: cantidad,
          );
        }
      }
    }
    return FilaRevisionMasiva(
      captura: f,
      actual: actual,
      errores: errores,
      cambio: errores.isNotEmpty
          ? null
          : CambioVarianteMasiva(
              clave: f.original.clave,
              baseProducto: f.baseProducto,
              oferta: oferta,
              venta: venta,
              costo: costo,
              precioProveedor: proveedor,
              entrada: entrada,
            ),
    );
  }

  String? _proveedor(String? id) {
    final value = id?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }
}
