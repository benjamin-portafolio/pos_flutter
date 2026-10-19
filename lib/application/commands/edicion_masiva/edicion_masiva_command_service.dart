import '../../config/app_config.dart';
import '../../edicion_masiva/cambio_variante_masiva.dart';
import '../../edicion_masiva/diario_edicion_masiva.dart';
import '../../edicion_masiva/entrada_mercancia_masiva.dart';
import '../../edicion_masiva/operacion_edicion_masiva.dart';
import '../../edicion_masiva/registro_operacion_masiva.dart';
import '../../edicion_masiva/resultado_ejecucion_masiva.dart';
import '../../edicion_masiva/resultado_operacion_masiva.dart';
import '../../sync/models/sync_event.dart';
import '../articulos/editar_articulo_comercial_command.dart';
import '../inventario/registrar_entrada_confirmada_command.dart';
import '../inventario/registrar_entrada_confirmada_result.dart';

/// Guarda por producto, secuencialmente. Una reserva no ejecuta negocio y un
/// resultado aplicado se consulta ANTES de exigir las bases antiguas.
class EdicionMasivaCommandService {
  const EdicionMasivaCommandService(this.diario);
  final DiarioEdicionMasiva diario;

  Future<List<OperacionEdicionMasiva>> confirmar({
    required String batchId,
    required Iterable<CambioVarianteMasiva> cambios,
  }) => diario.transaccion((u) async {
    final grupos = <String, List<CambioVarianteMasiva>>{};
    final variantes = <String>{};
    for (final c in cambios) {
      if (!variantes.add(c.clave.variantId)) {
        throw const FormatException('La variante está repetida.');
      }
      if (c.tieneCambios) {
        grupos.putIfAbsent(c.clave.productId, () => []).add(c);
      }
    }
    final operaciones = [
      for (final filas in grupos.values)
        OperacionEdicionMasiva.confirmada(
          batchId: batchId,
          modo: u.modo,
          cambios: filas,
        ),
    ];
    final existentes = await diario.listar(batchId: batchId);
    if (existentes.isNotEmpty &&
        (existentes.length != operaciones.length ||
            !existentes.every(
              (r) => operaciones.any(
                (o) => o.intencionJson == r.operacion.intencionJson,
              ),
            ))) {
      throw StateError('La captura ya fue confirmada con otra intención.');
    }
    for (final op in operaciones) {
      await diario.reservar(op);
    }
    return List.unmodifiable(operaciones);
  });

  Future<ResultadoOperacionMasiva> ejecutar(
    OperacionEdicionMasiva op,
  ) => diario.transaccion((u) async {
    final registro = await diario.buscar(op.operationId);
    if (registro == null ||
        registro.operacion.intencionJson != op.intencionJson) {
      throw StateError(
        'Operación no confirmada o identidad reutilizada con otra intención.',
      );
    }
    if (registro.estado == EstadoOperacionMasiva.aplicada) {
      return registro.resultado!;
    }
    if (registro.estado == EstadoOperacionMasiva.cerrada) {
      throw StateError('La revisión fue cerrada. Confirma una nueva captura.');
    }
    if (u.modo != op.modo) {
      throw StateError('La captura fue confirmada en otro modo.');
    }
    final lectura = await u.catalogo.leer(
      op.cambios.map((c) => c.clave).toSet(),
    );
    final entradas = <String, EntradaMercanciaMasiva>{};
    for (final c in op.cambios) {
      final actual = lectura.filas[c.clave];
      if (actual == null || !c.baseProducto.mismoEstado(actual.baseProducto)) {
        throw StateError(
          'El producto o la variante cambió. Revisa la captura.',
        );
      }
      if (c.entrada case final entrada?) {
        final base = actual.entrada;
        if (base == null || !entrada.base.mismoEstado(base)) {
          throw StateError(
            'El vínculo, recurso, unidad o saldo cambió. Revisa la entrada.',
          );
        }
        final id = base.recurso.id;
        final anterior = entradas[id];
        if (anterior != null && !anterior.base.mismoEstado(entrada.base)) {
          throw StateError('Las entradas del recurso tienen bases distintas.');
        }
        final suma =
            BigInt.from(anterior?.cantidadAtomic ?? 0) +
            BigInt.from(entrada.cantidadAtomic);
        if (suma > BigInt.from(9007199254740991)) {
          throw const FormatException(
            'La entrada acumulada excede el límite permitido.',
          );
        }
        entradas[id] = EntradaMercanciaMasiva(
          base: entrada.base,
          cantidadAtomic: suma.toInt(),
        );
      }
    }
    final comercial = await u.productos.editarArticuloComercial(
      EditarArticuloComercialCommand(
        productId: op.productId,
        base: op.cambios.first.baseProducto,
        cambios: op.cambios,
      ),
    );
    final movimientos = <RegistrarEntradaConfirmadaResult>[];
    for (final entrada in entradas.values) {
      movimientos.add(
        await u.inventario.registrarEntradaConfirmada(
          RegistrarEntradaConfirmadaCommand(
            base: entrada.base,
            cantidadAtomic: entrada.cantidadAtomic,
          ),
        ),
      );
    }
    final resultado = ResultadoOperacionMasiva(
      operationId: op.operationId,
      productId: op.productId,
      catalogEventId: comercial.eventId,
      entradas: movimientos,
    );
    await diario.completar(resultado);
    return resultado;
  });

  Future<List<RegistroOperacionMasiva>> registros({String? batchId}) =>
      diario.listar(batchId: batchId);

  Future<void> validarModo(AppMode modo) => diario.transaccion((u) async {
    if (u.modo != modo) {
      throw StateError('La captura fue confirmada en otro modo.');
    }
  });

  /// No se llama al arrancar. Revalida cada pendiente; conserva éxitos previos.
  Future<List<ResultadoEjecucionMasiva>> continuar(String batchId) async {
    final registros = await diario.listar(batchId: batchId);
    final resultados = <ResultadoEjecucionMasiva>[];
    for (final r in registros.where(
      (r) => r.estado != EstadoOperacionMasiva.cerrada,
    )) {
      try {
        resultados.add(
          ResultadoEjecucionMasiva(
            operacion: r.operacion,
            resultado: await ejecutar(r.operacion),
          ),
        );
      } catch (error) {
        resultados.add(
          ResultadoEjecucionMasiva(operacion: r.operacion, error: error),
        );
      }
    }
    return List.unmodifiable(resultados);
  }

  Future<List<RegistroOperacionMasiva>> pendientes() =>
      diario.listar(soloPendientes: true);

  /// Una propuesta obsoleta se cierra explícitamente; su sustituta usa otro
  /// batchId y solo incluye productos pendientes revisados por la persona.
  Future<void> cerrarPendientes(String batchId) =>
      diario.transaccion((_) => diario.cerrarPendientes(batchId));

  /// Estado actual de cada evento, independiente del commit guardado en diario.
  Future<List<SyncEvent>> eventos(ResultadoOperacionMasiva resultado) =>
      diario.transaccion((u) async {
        final originales = await diario.buscar(resultado.operationId);
        if (originales?.resultado?.json != resultado.json) {
          throw StateError(
            'El resultado no pertenece a esta operación aplicada.',
          );
        }
        return [
          for (final id in resultado.eventIds)
            await u.historial.eventById(id) ??
                (throw StateError('No se encontró el evento original $id.')),
        ];
      });
}
