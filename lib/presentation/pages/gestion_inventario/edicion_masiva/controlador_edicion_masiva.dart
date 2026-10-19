import 'package:flutter/widgets.dart';

import 'package:uuid/uuid.dart';

import '../../../../application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import '../../../../application/edicion_masiva/catalogo_edicion_masiva.dart';
import '../../../../application/edicion_masiva/clave_variante.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../../../application/edicion_masiva/operacion_edicion_masiva.dart';
import '../../../../application/edicion_masiva/registro_operacion_masiva.dart';
import '../../../../application/edicion_masiva/resultado_operacion_masiva.dart';
import '../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../domain/proveedores/proveedor.dart';
import 'borrador_edicion_masiva.dart';
import 'fila_edicion_form.dart';
import 'fila_revision_masiva.dart';
import 'revision_edicion_masiva.dart';
import 'resultado_guardado_masivo.dart';

enum CampoTextoEdicion { venta, costo, cantidad }

/// Estado de ambas vistas sobre el borrador compartido. Ningún método de
/// captura escribe en la base. El guardado delega al coordinador transaccional
/// exclusivamente desde una revisión confirmada.
class ControladorEdicionMasiva extends ChangeNotifier {
  ControladorEdicionMasiva({
    required CatalogoEdicionMasiva catalogo,
    required this.comando,
    BorradorEdicionMasiva? borrador,
    DateTime Function()? ahora,
  }) : borrador =
           borrador ?? BorradorEdicionMasiva(catalogo: catalogo, ahora: ahora);

  static const tamanoPagina = 100;

  final BorradorEdicionMasiva borrador;
  final EdicionMasivaCommandService comando;

  /// Cambios del contador de variantes modificadas (una pulsación no reconstruye
  /// el listado ni los campos).
  final contador = ChangeNotifier();

  final _filas = <FilaCatalogoMasivo>[];
  final _paginasCargadas = <ClaveVariante, _ControladoresFila>{};
  final _notasFilas = <ClaveVariante, ChangeNotifier>{};
  final _nombresProductos = <String, String>{};
  final _ediciones = <Future<void>>{};
  final _errores = <ClaveVariante, String>{};
  final _revisadas = <ClaveVariante, FilaRevisionMasiva>{};
  List<OperacionEdicionMasiva> _pendientes = [];
  final _resultadosPorRevision = Expando<List<ResultadoGuardadoMasivo>>();
  Object? errorCarga;
  Object? errorProveedores;
  Object? errorRecuperacion;
  int capturasPorRecuperar = 0;
  var _generacion = 0;
  var _pagina = 0;
  var _cargando = false;
  var _hayMasPaginas = true;
  var _proveedores = const <Proveedor>[];
  _GuardadoEnCurso? _guardado;
  var _disposed = false;

  List<FilaCatalogoMasivo> get filasCargadas => List.unmodifiable(_filas);
  bool get cargando => _cargando;
  bool get hayMasPaginas => _hayMasPaginas;
  List<Proveedor> get proveedores => _proveedores;
  bool modificada(ClaveVariante clave) =>
      borrador.filas.containsKey(clave) &&
      borrador.revisarCaptura(clave).estado != EstadoFilaMasiva.sinCambios;
  int get modificadas => borrador.filas.keys.where(modificada).length;
  Map<CampoEdicionMasiva, String> erroresFila(ClaveVariante clave) =>
      _revisadas[clave]?.errores ??
      (borrador.filas.containsKey(clave)
          ? borrador.revisarCaptura(clave).errores
          : const {});
  String? errorCaptura(ClaveVariante clave) => _errores[clave];
  bool get tieneCapturas =>
      borrador.filas.isNotEmpty || _ediciones.isNotEmpty || _errores.isNotEmpty;
  bool get guardando => _guardado != null;
  int get productosGuardados => _guardado?.avance ?? 0;
  int get productosAGuardar => _guardado?.total ?? 0;
  bool get cancelacionSolicitada => _guardado?.cancelado ?? false;
  VistaEdicionMasiva get vista => borrador.vista;
  TareaEdicionMasiva get tarea => borrador.tarea;

  void cambiarVista(VistaEdicionMasiva valor) {
    borrador.vista = valor;
    _notificarEstructura();
  }

  bool get soloCambios => borrador.soloCambios;

  /// Filas listadas por la vista: páginas del catálogo, o las capturas que
  /// coinciden con la búsqueda cuando «Solo cambios» está activo.
  List<FilaCatalogoMasivo> get filasListadas {
    if (!borrador.soloCambios) return List.unmodifiable(_filas);
    final query = borrador.busqueda.trim().toLowerCase();
    return List.unmodifiable(
      borrador.filas.values
          .where((f) => modificada(f.original.clave))
          .map((f) => f.original)
          .where(
            (f) =>
                query.isEmpty ||
                f.nombreProducto.toLowerCase().contains(query) ||
                (f.nombreVariante ?? '').toLowerCase().contains(query),
          ),
    );
  }

  void proveedoresActualizados(List<Proveedor> valores) {
    if (_disposed) return;
    errorProveedores = null;
    _proveedores = List.unmodifiable(valores);
    _notificarEstructura();
  }

  void falloProveedores(Object error) {
    if (_disposed) return;
    errorProveedores = error;
    _notificarEstructura();
  }

  void _textoVigente(TextEditingController controller, String texto) {
    if (controller.text != texto) controller.text = texto;
  }

  Future<void> buscar() async {
    if (_disposed) return;
    final generacion = ++_generacion;
    _cargando = true;
    errorCarga = null;
    _notificarEstructura();
    try {
      final pagina = await borrador.buscar(limite: tamanoPagina);
      if (_disposed || generacion != _generacion) return;
      _filas
        ..clear()
        ..addAll(pagina);
      for (final fila in pagina) {
        final textos = _paginasCargadas[fila.clave];
        final captura = borrador.filas[fila.clave];
        if (textos == null || _ediciones.isNotEmpty) continue;
        const importes = ImporteComercialCodec();
        if (captura?.venta == null) {
          _textoVigente(textos.venta, importes.format(fila.ventaMinor));
        }
        if (captura?.costo == null) {
          _textoVigente(
            textos.costo,
            fila.costoMinor == null ? '' : importes.format(fila.costoMinor!),
          );
        }
      }
      _pagina = 1;
      _hayMasPaginas = pagina.length == tamanoPagina;
    } catch (error) {
      if (!_disposed && generacion == _generacion) errorCarga = error;
    } finally {
      if (!_disposed && generacion == _generacion) {
        _cargando = false;
        _notificarEstructura();
      }
    }
  }

  Future<void> cargarMas() async {
    if (_disposed || _cargando || !_hayMasPaginas || soloCambios) return;
    final generacion = _generacion;
    _cargando = true;
    errorCarga = null;
    _notificarEstructura();
    try {
      final pagina = await borrador.buscar(
        limite: tamanoPagina,
        desplazamiento: _pagina * tamanoPagina,
      );
      if (_disposed || generacion != _generacion) return;
      final conocidas = _filas.map((f) => f.clave).toSet();
      _filas.addAll(pagina.where((f) => conocidas.add(f.clave)));
      _pagina += 1;
      _hayMasPaginas = pagina.length == tamanoPagina;
    } catch (error) {
      if (!_disposed && generacion == _generacion) errorCarga = error;
    } finally {
      if (!_disposed && generacion == _generacion) {
        _cargando = false;
        _notificarEstructura();
      }
    }
  }

  Future<void> cambiarBusqueda(String texto) async {
    if (borrador.busqueda == texto) return;
    borrador.busqueda = texto;
    await buscar();
  }

  void cambiarSoloCambios(bool valor) {
    borrador.soloCambios = valor;
    _notificarEstructura();
  }

  void cambiarTarea(TareaEdicionMasiva valor) {
    borrador.tarea = valor;
    _notificarEstructura();
  }

  /// Solo predetermina nuevas capturas de costo; las filas ya capturadas
  /// conservan su proveedor.
  void elegirProveedorGlobal(String? proveedorId) {
    borrador.elegirProveedorGlobal(proveedorId);
    _notificarEstructura();
  }

  TextEditingController controladorTexto(
    ClaveVariante clave,
    CampoTextoEdicion campo, {
    FilaCatalogoMasivo? original,
  }) {
    final fila = _paginasCargadas.putIfAbsent(clave, () {
      final captura = borrador.filas[clave];
      final base = captura?.original ?? original;
      const importes = ImporteComercialCodec();
      return _ControladoresFila(
        venta:
            captura?.venta ??
            (base == null ? '' : importes.format(base.ventaMinor)),
        costo:
            captura?.costo ??
            (base?.costoMinor == null
                ? ''
                : importes.format(base!.costoMinor!)),
        cantidad: captura?.cantidad ?? '',
      );
    });
    switch (campo) {
      case CampoTextoEdicion.venta:
        return fila.venta;
      case CampoTextoEdicion.costo:
        return fila.costo;
      case CampoTextoEdicion.cantidad:
        return fila.cantidad;
    }
  }

  CampoTextoEdicion? campoSeleccionado;

  FocusNode foco(ClaveVariante clave, [CampoTextoEdicion? campo]) {
    if (!_paginasCargadas.containsKey(clave)) {
      final original = _filas.where((f) => f.clave == clave).firstOrNull;
      controladorTexto(clave, CampoTextoEdicion.venta, original: original);
    }
    final fila = _paginasCargadas[clave]!;
    final efectivo =
        campo ??
        (vista == VistaEdicionMasiva.recepcionCompacta
            ? CampoTextoEdicion.costo
            : switch (tarea) {
                TareaEdicionMasiva.venta => CampoTextoEdicion.venta,
                TareaEdicionMasiva.costoProveedor => CampoTextoEdicion.costo,
                TareaEdicionMasiva.agregarExistencias =>
                  CampoTextoEdicion.cantidad,
              });
    final node = fila.focos[efectivo]!;
    node.debugLabel ??= 'edicion-masiva-${clave.variantId}';
    return node;
  }

  ChangeNotifier notificadorFila(ClaveVariante clave) =>
      _notasFilas.putIfAbsent(clave, ChangeNotifier.new);

  FilaEdicionForm? captura(ClaveVariante clave) => borrador.filas[clave];

  Future<void> editarVenta(ClaveVariante clave, String texto) =>
      _editarCaptura(clave, () => borrador.editarVenta(clave, texto));

  Future<void> editarCosto(ClaveVariante clave, String texto) =>
      _editarCaptura(clave, () => borrador.editarCosto(clave, texto));

  Future<void> editarCantidad(ClaveVariante clave, String texto) =>
      _editarCaptura(clave, () => borrador.editarCantidad(clave, texto));

  Future<void> editarProveedorFila(
    ClaveVariante clave,
    String? proveedorId, {
    DateTime? fecha,
  }) => _editarCaptura(
    clave,
    () => borrador.editarProveedor(clave, proveedorId, fecha: fecha),
  );

  Future<void> _editarCaptura(
    ClaveVariante clave,
    Future<void> Function() editar,
  ) async {
    if (_disposed || guardando) return;
    final antes = modificada(clave);
    final pendiente = editar();
    _ediciones.add(pendiente);
    contador.notifyListeners();
    try {
      await pendiente;
      if (_disposed) return;
      _errores.remove(clave);
      _revisadas.remove(clave);
    } catch (error) {
      if (_disposed) return;
      _errores[clave] = mensajeLegibleEdicionMasiva(error);
    } finally {
      _ediciones.remove(pendiente);
    }
    if (_disposed) return;
    notificadorFila(clave).notifyListeners();
    contador.notifyListeners();
    if (soloCambios && antes != modificada(clave)) _notificarEstructura();
  }

  void retirarFila(ClaveVariante clave) {
    borrador.retirarFila(clave);
    _errores.remove(clave);
    _revisadas.remove(clave);
    // Los widgets todavía pueden estar montados: conservar los objetos hasta
    // dispose y restablecer su texto sin destruir un FocusNode en uso.
    final textos = _paginasCargadas[clave];
    if (textos != null) {
      final original = _filas.where((f) => f.clave == clave).firstOrNull;
      const importes = ImporteComercialCodec();
      textos.venta.text = original == null
          ? ''
          : importes.format(original.ventaMinor);
      textos.costo.text = original?.costoMinor == null
          ? ''
          : importes.format(original!.costoMinor!);
      textos.cantidad.clear();
    }
    _notasFilas[clave]?.notifyListeners();
    contador.notifyListeners();
    _notificarEstructura();
  }

  /// Reúne todo el borrador, incluidas las filas ocultas por búsqueda o filtro.
  Future<RevisionEdicionMasiva> prepararRevision() async {
    await Future.wait(_ediciones.toList());
    if (_disposed) throw StateError('La pantalla fue cerrada.');
    if (_errores.isNotEmpty) throw StateError(_errores.values.first);
    final revision = await borrador.prepararRevision();
    if (_disposed) throw StateError('La pantalla fue cerrada.');
    _revisadas
      ..clear()
      ..addEntries(
        revision.filas.map((f) => MapEntry(f.captura.original.clave, f)),
      );
    _nombresProductos.addAll({
      for (final fila in revision.filas)
        fila.captura.original.clave.productId:
            fila.captura.original.nombreProducto,
    });
    return revision;
  }

  String nombreProducto(String productId) =>
      _nombresProductos[productId] ?? productId;

  String nombreProveedor(String id) {
    for (final proveedor in _proveedores) {
      if (proveedor.id == id) return proveedor.nombre;
    }
    return id;
  }

  /// Confirma la captura una sola vez y aplica cada producto secuencialmente.
  /// Una salida de la revisión cancela los productos aún no iniciados; los ya
  /// confirmados en el diario quedan para la recuperación.
  Future<List<ResultadoGuardadoMasivo>> guardar(
    RevisionEdicionMasiva revision,
  ) async {
    if (_disposed) return const [];
    if (guardando) throw StateError('Ya hay un guardado en curso.');
    final anterior = _resultadosPorRevision[revision];
    if (anterior != null) return anterior;
    final cambios = revision.cambios;
    final enCurso = _GuardadoEnCurso(const Uuid().v4());
    _guardado = enCurso;
    _notificarEstructura();
    List<OperacionEdicionMasiva> operaciones;
    try {
      if (_pendientes.isNotEmpty) {
        if (cambios.any(
          (c) => !_pendientes.any((op) => op.productId == c.clave.productId),
        )) {
          throw StateError(
            'Termina la captura confirmada pendiente antes de agregar otros productos.',
          );
        }
        for (final op in _pendientes) {
          if (!cambios.any((c) => c.clave.productId == op.productId)) {
            throw StateError(
              'Una captura confirmada fue retirada o ya no tiene diferencias. Usa Revisar sobre estado nuevo para cerrar sus pendientes.',
            );
          }
          final propuesta = OperacionEdicionMasiva.confirmada(
            batchId: op.batchId,
            modo: op.modo,
            cambios: cambios.where((c) => c.clave.productId == op.productId),
          );
          if (propuesta.intencionJson != op.intencionJson) {
            throw StateError(
              'La captura confirmada cambió. Revisa y resuelve la operación pendiente antes de reemplazarla.',
            );
          }
        }
        operaciones = List.of(_pendientes);
      } else {
        final anteriores = await comando.pendientes();
        if (_disposed || enCurso.cancelado) {
          _finalizarGuardado(enCurso);
          return const [];
        }
        if (anteriores.any(
          (r) => cambios.any((c) => c.clave.productId == r.operacion.productId),
        )) {
          throw StateError(
            'Hay una captura confirmada pendiente para este producto. Revisa su recuperación antes de confirmar otra.',
          );
        }
        operaciones = await comando.confirmar(
          batchId: enCurso.batchId,
          cambios: cambios,
        );
        _pendientes = List.of(operaciones);
      }
    } catch (_) {
      _finalizarGuardado(enCurso);
      rethrow;
    }
    final omitidos = revision.filas
        .map((f) => f.captura.original.clave.productId)
        .toSet()
        .where((id) => !operaciones.any((op) => op.productId == id));
    final resultados = await _ejecutar(operaciones, enCurso);
    final completos = List<ResultadoGuardadoMasivo>.unmodifiable([
      ...resultados,
      for (final id in omitidos) ResultadoGuardadoMasivo.omitida(productId: id),
    ]);
    if (!_disposed && resultados.every((r) => r.aplicada)) {
      descartarCapturas();
      _resultadosPorRevision[revision] = completos;
    }
    return completos;
  }

  Future<void> consultarPendientes() async {
    try {
      final pendientes = await comando.pendientes();
      if (_disposed) return;
      capturasPorRecuperar = pendientes
          .map((r) => r.operacion.batchId)
          .toSet()
          .length;
      errorRecuperacion = null;
    } catch (error) {
      if (_disposed) return;
      errorRecuperacion = error;
    }
    _notificarEstructura();
  }

  /// Lee evidencia; nunca continúa una captura al abrir la pantalla.
  Future<List<RegistroOperacionMasiva>> registros() async {
    final registros = await comando.registros();
    final claves = registros
        .expand((r) => r.operacion.cambios)
        .map((c) => c.clave)
        .toSet();
    final lectura = await borrador.catalogo.leer(claves);
    for (final fila in lectura.filas.values) {
      _nombresProductos[fila.clave.productId] = fila.nombreProducto;
    }
    return registros;
  }

  Future<List<ResultadoGuardadoMasivo>> continuarCaptura(String batchId) async {
    if (guardando) throw StateError('Ya hay un guardado en curso.');
    final enCurso = _GuardadoEnCurso(batchId);
    _guardado = enCurso;
    _notificarEstructura();
    try {
      final registros = await comando.registros(batchId: batchId);
      final operaciones = registros
          .where((r) => r.estado != EstadoOperacionMasiva.cerrada)
          .map((r) => r.operacion)
          .toList();
      if (registros
          .where((r) => r.estado == EstadoOperacionMasiva.confirmada)
          .any(
            (r) => borrador.filas.keys.any(
              (clave) => clave.productId == r.operacion.productId,
            ),
          )) {
        throw StateError(
          'Hay capturas en edición para estos productos. Usa Revisar pendientes para conservarlas y confirmar su intención.',
        );
      }
      final resultados = await _ejecutar(
        operaciones,
        enCurso,
        aplicadas: {
          for (final r in registros)
            if (r.resultado != null) r.operacion.operationId: r.resultado!,
        },
      );
      return List.unmodifiable([
        ...resultados,
        for (final r in registros)
          if (r.estado == EstadoOperacionMasiva.cerrada)
            ResultadoGuardadoMasivo.omitida(productId: r.operacion.productId),
      ]);
    } finally {
      _finalizarGuardado(enCurso);
    }
  }

  Future<List<ResultadoGuardadoMasivo>> _ejecutar(
    List<OperacionEdicionMasiva> operaciones,
    _GuardadoEnCurso enCurso, {
    Map<String, ResultadoOperacionMasiva> aplicadas = const {},
  }) async {
    enCurso.total = operaciones.length;
    final resultados = <ResultadoGuardadoMasivo>[];
    try {
      for (final operacion in operaciones) {
        if (aplicadas[operacion.operationId] case final resultado?) {
          resultados.add(
            ResultadoGuardadoMasivo.aplicada(
              productId: operacion.productId,
              resultado: resultado,
            ),
          );
          enCurso.avance++;
          _notificarEstructura();
          continue;
        }
        if (_disposed || enCurso.cancelado) {
          resultados.add(
            ResultadoGuardadoMasivo.pendiente(productId: operacion.productId),
          );
          continue;
        }
        try {
          final resultado = await comando.ejecutar(operacion);
          resultados.add(
            ResultadoGuardadoMasivo.aplicada(
              productId: operacion.productId,
              resultado: resultado,
            ),
          );
          _pendientes.removeWhere(
            (op) => op.operationId == operacion.operationId,
          );
          if (!_disposed) {
            for (final c in operacion.cambios) {
              retirarFila(c.clave);
            }
          }
        } catch (error) {
          resultados.add(
            ResultadoGuardadoMasivo.fallida(
              productId: operacion.productId,
              error: error,
            ),
          );
        }
        // ejecutar solo responde después del commit/rollback exterior.
        enCurso.avance++;
        _notificarEstructura();
      }
      return List.unmodifiable(resultados);
    } finally {
      _finalizarGuardado(enCurso);
    }
  }

  Future<void> cerrarCaptura(String batchId) async {
    if (guardando) throw StateError('Espera a que termine el guardado.');
    await comando.cerrarPendientes(batchId);
    final retiradas = _pendientes.where((op) => op.batchId == batchId).toList();
    _pendientes.removeWhere((op) => op.batchId == batchId);
    for (final op in retiradas) {
      for (final c in op.cambios) {
        retirarFila(c.clave);
      }
    }
  }

  /// Copia exclusivamente pendientes; los aplicados nunca vuelven al borrador.
  Future<void> recuperarParaRevision(String batchId) async {
    if (guardando) throw StateError('Espera a que termine el guardado.');
    final registros = await comando.registros(batchId: batchId);
    final pendientes = registros
        .where((r) => r.estado == EstadoOperacionMasiva.confirmada)
        .toList();
    if (pendientes.isEmpty) throw StateError('No quedan productos pendientes.');
    await comando.validarModo(pendientes.first.operacion.modo);
    final claves = pendientes
        .expand((r) => r.operacion.cambios)
        .map((c) => c.clave)
        .toSet();
    if (borrador.filas.keys.any((k) => !claves.contains(k))) {
      throw StateError(
        'Conserva o descarta primero la captura que estás editando.',
      );
    }
    await borrador.recuperar(pendientes.map((r) => r.operacion));
    if (_disposed) return;
    _pendientes = pendientes.map((r) => r.operacion).toList();
    _sincronizarTextos();
    await prepararRevision();
    _notificarEstructura();
  }

  /// Acción explícita: conserva textos, relee bases y cierra reservas antiguas.
  /// La siguiente confirmación tendrá otra identidad y exigirá revisar de nuevo.
  Future<void> revisarEstadoNuevo() async {
    if (guardando) throw StateError('Espera a que termine el guardado.');
    for (final op in _pendientes) {
      await comando.validarModo(op.modo);
    }
    await borrador.revisarEstadoNuevo();
    for (final batch in _pendientes.map((op) => op.batchId).toSet()) {
      await comando.cerrarPendientes(batch);
    }
    _pendientes = [];
    for (var i = 0; i < _filas.length; i++) {
      _filas[i] = borrador.filas[_filas[i].clave]?.original ?? _filas[i];
    }
    _revisadas.clear();
    _sincronizarTextos();
    _notificarEstructura();
  }

  void _sincronizarTextos() {
    for (final captura in borrador.filas.values) {
      _nombresProductos[captura.original.clave.productId] =
          captura.original.nombreProducto;
      final clave = captura.original.clave;
      for (final campo in CampoTextoEdicion.values) {
        final texto = switch (campo) {
          CampoTextoEdicion.venta =>
            captura.venta ??
                const ImporteComercialCodec().format(
                  captura.original.ventaMinor,
                ),
          CampoTextoEdicion.costo =>
            captura.costo ??
                (captura.original.costoMinor == null
                    ? ''
                    : const ImporteComercialCodec().format(
                        captura.original.costoMinor!,
                      )),
          CampoTextoEdicion.cantidad => captura.cantidad ?? '',
        };
        _textoVigente(controladorTexto(clave, campo), texto);
      }
      _notasFilas[clave]?.notifyListeners();
    }
    contador.notifyListeners();
  }

  void cancelarGuardado({bool notificar = true}) {
    final enCurso = _guardado;
    if (enCurso != null) enCurso.cancelado = true;
    if (notificar) _notificarEstructura();
  }

  /// Retira todas las capturas sin tocar la base; también tras un guardado
  /// completo, cuyas operaciones ya viven en el diario.
  void descartarCapturas() {
    for (final clave in borrador.filas.keys.toList()) {
      retirarFila(clave);
    }
    contador.notifyListeners();
    _notificarEstructura();
  }

  void _finalizarGuardado(_GuardadoEnCurso enCurso) {
    if (identical(_guardado, enCurso)) _guardado = null;
    _notificarEstructura();
  }

  void _notificarEstructura() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelarGuardado(notificar: false);
    for (final fila in _paginasCargadas.values) {
      fila.dispose();
    }
    for (final nota in _notasFilas.values) {
      nota.dispose();
    }
    _paginasCargadas.clear();
    _notasFilas.clear();
    contador.dispose();
    super.dispose();
  }
}

class _ControladoresFila {
  _ControladoresFila({
    String venta = '',
    String costo = '',
    String cantidad = '',
  }) : venta = TextEditingController(text: venta),
       costo = TextEditingController(text: costo),
       cantidad = TextEditingController(text: cantidad);
  final TextEditingController venta;
  final TextEditingController costo;
  final TextEditingController cantidad;
  final focos = {
    for (final campo in CampoTextoEdicion.values) campo: FocusNode(),
  };

  void dispose() {
    venta.dispose();
    costo.dispose();
    cantidad.dispose();
    for (final node in focos.values) {
      node.dispose();
    }
  }
}

class _GuardadoEnCurso {
  _GuardadoEnCurso(this.batchId);
  final String batchId;
  bool cancelado = false;
  int total = 0;
  int avance = 0;
}
