import 'recovery_product_shape.dart';
import '../sync/payloads/abono_cliente_registrado_payload.dart';
import '../sync/payloads/caja_abierta_payload.dart';
import '../sync/payloads/caja_cerrada_payload.dart';
import '../sync/payloads/categoria_actualizada_payload.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/payloads/categoria_eliminada_payload.dart';
import '../sync/payloads/categoria_movida_payload.dart';
import '../sync/payloads/categoria_financiera_creada_payload.dart';
import '../sync/payloads/cliente_creado_payload.dart';
import '../sync/payloads/cliente_actualizado_payload.dart';
import '../sync/payloads/espacio_creado_payload.dart';
import '../sync/payloads/movimiento_financiero_registrado_payload.dart';
import '../sync/payloads/movimiento_inventario_registrado_payload.dart';
import '../sync/payloads/operacion_venta_conciliada_payload.dart';
import '../sync/payloads/producto_creado_payload.dart';
import '../sync/payloads/producto_actualizado_payload.dart';
import '../sync/payloads/proveedor_creado_payload.dart';
import '../sync/payloads/proveedor_actualizado_payload.dart';
import '../sync/payloads/recurso_inventario_creado_payload.dart';
import '../sync/payloads/recurso_inventario_actualizado_payload.dart';
import '../sync/payloads/recurso_inventario_eliminado_payload.dart';
import '../sync/payloads/saldo_cuenta_inicial_declarado_payload.dart';
import '../sync/payloads/venta_confirmada_payload.dart';
import '../sync/payloads/venta_anulada_payload.dart';
import '../sync/payloads/devolucion_venta_registrada_payload.dart';

/// Parsers puros existentes; nunca ejecuta handlers ni reserializa la evidencia.
class RecoveryEventContract {
  static void _shape(
    Object? original,
    Object? typed, [
    String path = '',
    String eventType = '',
  ]) {
    if (original is Map && typed is Map) {
      for (final key in original.keys) {
        final next = path.isEmpty ? '$key' : '$path.$key';
        if (!typed.containsKey(key)) {
          if (original[key] == null &&
              ((next == 'inventory_item.origin_variant_id' &&
                      eventType == RecursoInventarioCreadoPayload.eventType) ||
                  (next == 'cash' &&
                      {
                        AbonoClienteRegistradoPayload.eventType,
                        MovimientoFinancieroRegistradoPayload.eventType,
                        VentaConfirmadaPayload.eventType,
                      }.contains(eventType)))) {
            continue;
          }
          throw FormatException('Campo no admitido: $key');
        }
        _shape(original[key], typed[key], next, eventType);
      }
    } else if (original is List && typed is List) {
      if (original.length != typed.length) {
        throw FormatException('Forma de lista incompatible: $path');
      }
      for (var i = 0; i < original.length; i++) {
        _shape(original[i], typed[i], '$path[$i]', eventType);
      }
    }
  }

  static bool supports(String type) => _aggregates.containsKey(type);
  static const _aggregates = <String, String>{
    AbonoClienteRegistradoPayload.eventType:
        AbonoClienteRegistradoPayload.aggregateType,
    CajaAbiertaPayload.eventType: CajaAbiertaPayload.aggregateType,
    CajaCerradaPayload.eventType: CajaCerradaPayload.aggregateType,
    CategoriaActualizadaPayload.eventType:
        CategoriaActualizadaPayload.aggregateType,
    CategoriaCreadaPayload.eventType: CategoriaCreadaPayload.aggregateType,
    CategoriaEliminadaPayload.eventType:
        CategoriaEliminadaPayload.aggregateType,
    CategoriaMovidaPayload.eventType: CategoriaMovidaPayload.aggregateType,
    CategoriaFinancieraCreadaPayload.eventType:
        CategoriaFinancieraCreadaPayload.aggregateType,
    ClienteCreadoPayload.eventType: ClienteCreadoPayload.aggregateType,
    ClienteActualizadoPayload.eventType:
        ClienteActualizadoPayload.aggregateType,
    EspacioCreadoPayload.eventType: EspacioCreadoPayload.aggregateType,
    MovimientoFinancieroRegistradoPayload.eventType:
        MovimientoFinancieroRegistradoPayload.aggregateType,
    MovimientoInventarioRegistradoPayload.eventType:
        MovimientoInventarioRegistradoPayload.aggregateType,
    OperacionVentaConciliadaPayload.eventType:
        OperacionVentaConciliadaPayload.aggregateType,
    ProductoCreadoPayload.eventType: ProductoCreadoPayload.aggregateType,
    ProductoActualizadoPayload.eventType:
        ProductoActualizadoPayload.aggregateType,
    ProveedorCreadoPayload.eventType: ProveedorCreadoPayload.aggregateType,
    ProveedorActualizadoPayload.eventType:
        ProveedorActualizadoPayload.aggregateType,
    RecursoInventarioCreadoPayload.eventType:
        RecursoInventarioCreadoPayload.aggregateType,
    RecursoInventarioActualizadoPayload.eventType:
        RecursoInventarioActualizadoPayload.aggregateType,
    RecursoInventarioEliminadoPayload.eventType:
        RecursoInventarioEliminadoPayload.aggregateType,
    SaldoCuentaInicialDeclaradoPayload.eventType:
        SaldoCuentaInicialDeclaradoPayload.aggregateType,
    VentaConfirmadaPayload.eventType: VentaConfirmadaPayload.aggregateType,
    VentaAnuladaPayload.eventType: VentaAnuladaPayload.aggregateType,
    DevolucionVentaRegistradaPayload.eventType:
        DevolucionVentaRegistradaPayload.aggregateType,
  };
  static void assertAggregate(String type, String aggregate) {
    if (_aggregates[type] != aggregate) {
      throw const FormatException('Tipo de agregado incompatible.');
    }
  }

  static Iterable<String> dependencies(String type, Map<String, Object?> json) {
    switch (type) {
      case AbonoClienteRegistradoPayload.eventType:
        final p = AbonoClienteRegistradoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.dependencyEventIds;
      case CajaAbiertaPayload.eventType:
        final p = CajaAbiertaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.dependencyEventIds;
      case CajaCerradaPayload.eventType:
        final p = CajaCerradaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.dependencyEventIds;
      case CategoriaActualizadaPayload.eventType:
        final p = CategoriaActualizadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case CategoriaCreadaPayload.eventType:
        final p = CategoriaCreadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case CategoriaEliminadaPayload.eventType:
        final p = CategoriaEliminadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [
          p.baseEventId,
          p.categoriaEliminada.createdEventId,
          ?p.resolucionProductos.categoriaDestino?.baseEventId,
          ...p.productosVinculados.map((x) => x.baseEventId),
          ...p.categoriasDesplazadas.map((x) => x.baseEventId),
        ];
      case CategoriaMovidaPayload.eventType:
        final p = CategoriaMovidaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId, p.categoriaDesplazadaBaseEventId];
      case CategoriaFinancieraCreadaPayload.eventType:
        final p = CategoriaFinancieraCreadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case ClienteCreadoPayload.eventType:
        final p = ClienteCreadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case ClienteActualizadoPayload.eventType:
        final p = ClienteActualizadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case EspacioCreadoPayload.eventType:
        final p = EspacioCreadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case MovimientoFinancieroRegistradoPayload.eventType:
        final p = MovimientoFinancieroRegistradoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.dependencyEventIds;
      case MovimientoInventarioRegistradoPayload.eventType:
        final p = MovimientoInventarioRegistradoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case OperacionVentaConciliadaPayload.eventType:
        final p = OperacionVentaConciliadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.dependencyEventIds;
      case ProductoCreadoPayload.eventType:
        final p = ProductoCreadoPayload.fromJson(json);
        RecoveryProductShape.validate(json, updated: false);
        return [
          ?p.dependenciaCategoria?.dependsOnEventId,
          ...p.dependenciasInventario
              .map((d) => d.dependsOnEventId)
              .whereType<String>(),
          ...p.dependenciasProveedores
              .map((d) => d.dependsOnEventId)
              .whereType<String>(),
        ];
      case ProductoActualizadoPayload.eventType:
        final p = ProductoActualizadoPayload.fromJson(json);
        RecoveryProductShape.validate(json, updated: true);
        return p.dependencyEventIds;
      case ProveedorCreadoPayload.eventType:
        final p = ProveedorCreadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case ProveedorActualizadoPayload.eventType:
        final p = ProveedorActualizadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case RecursoInventarioCreadoPayload.eventType:
        final p = RecursoInventarioCreadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case RecursoInventarioActualizadoPayload.eventType:
        final p = RecursoInventarioActualizadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case RecursoInventarioEliminadoPayload.eventType:
        final p = RecursoInventarioEliminadoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return [p.baseEventId];
      case SaldoCuentaInicialDeclaradoPayload.eventType:
        final p = SaldoCuentaInicialDeclaradoPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return const [];
      case VentaConfirmadaPayload.eventType:
        final p = VentaConfirmadaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return {
          ...p.dependencyEventIds,
          ...p.lines.map((l) => l.configurationEventId),
        };
      case VentaAnuladaPayload.eventType:
        final p = VentaAnuladaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.adjustment.dependencyEventIds;
      case DevolucionVentaRegistradaPayload.eventType:
        final p = DevolucionVentaRegistradaPayload.fromJson(json);
        _shape(json, p.toJson(), '', type);
        return p.adjustment.dependencyEventIds;
      default:
        throw UnsupportedError('Contrato de evento incompatible: $type');
    }
  }
}
