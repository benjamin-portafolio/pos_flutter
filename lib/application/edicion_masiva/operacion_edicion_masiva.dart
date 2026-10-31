import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/articulos/costo_estandar.dart';
import '../../domain/articulos/precio_venta.dart';
import '../../domain/articulos/proveedor_variante.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../config/app_config.dart';
import 'base_entrada_masiva.dart';
import 'base_revision_masiva.dart';
import 'cambio_explicito.dart';
import 'cambio_variante_masiva.dart';
import 'clave_variante.dart';
import 'entrada_mercancia_masiva.dart';

/// Solicitud confirmada e inmutable. Una captura/producto siempre obtiene la
/// misma identidad; el JSON canónico conserva intención y bases para reabrir.
class OperacionEdicionMasiva {
  OperacionEdicionMasiva._(this.batchId, this.modo, this.cambios);

  factory OperacionEdicionMasiva.confirmada({
    required String batchId,
    required AppMode modo,
    required Iterable<CambioVarianteMasiva> cambios,
  }) {
    final filas = cambios.toList()
      ..sort((a, b) => a.clave.variantId.compareTo(b.clave.variantId));
    if (batchId.isEmpty || batchId.trim() != batchId || filas.isEmpty) {
      throw const FormatException('La captura y sus cambios son obligatorios.');
    }
    final base = filas.first.baseProducto;
    final ids = <String>{};
    for (final fila in filas) {
      if (fila.clave.productId != base.id ||
          !fila.baseProducto.mismoEstado(base) ||
          !ids.add(fila.clave.variantId) ||
          fila.clave.variantId.isEmpty ||
          base.id.isEmpty ||
          base.version < 1 ||
          base.eventId == null ||
          !fila.tieneCambios) {
        throw const FormatException(
          'Identidad, base o variante inválida/repetida.',
        );
      }
      if (fila.venta.establecer) {
        PrecioVenta.fromUnidadMenor(fila.venta.valor);
      }
      if (fila.oferta.establecer && fila.oferta.valor != null) {
        PrecioVenta.fromUnidadMenor(fila.oferta.valor!);
      }
      if (fila.costo.establecer) {
        CostoEstandar.fromUnidadMenor(fila.costo.valor);
      }
    }
    return OperacionEdicionMasiva._(batchId, modo, List.unmodifiable(filas));
  }

  final String batchId;
  final AppMode modo;
  final List<CambioVarianteMasiva> cambios;
  String get productId => cambios.first.clave.productId;
  String get operationId => const Uuid().v5(
    Namespace.url.value,
    jsonEncode(['pos/edicion_masiva/v1', batchId, productId]),
  );

  String get intencionJson => jsonEncode({
    'format': 1,
    'batch_id': batchId,
    'mode': modo.storageValue,
    'changes': cambios
        .map(
          (c) => {
            'product_id': c.clave.productId,
            'variant_id': c.clave.variantId,
            'product_base': _baseJson(c.baseProducto),
            if (c.oferta.establecer) 'offer_minor': c.oferta.valor,
            'sale_minor': c.venta.establecer ? c.venta.valor : null,
            'cost_minor': c.costo.establecer ? c.costo.valor : null,
            'supplier': c.precioProveedor == null
                ? null
                : {
                    'id': c.precioProveedor!.proveedorId,
                    'price_minor': c.precioProveedor!.precioInformadoMenor,
                    'quoted_at_ms': c.precioProveedor!.fechaInformadaMs,
                  },
            'receipt': c.entrada == null ? null : _entradaJson(c.entrada!),
          },
        )
        .toList(),
  });

  factory OperacionEdicionMasiva.fromJson(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['format'] != 1 ||
        !{'standalone', 'server_sync'}.contains(json['mode'])) {
      throw const FormatException('Formato de operación desconocido.');
    }
    return OperacionEdicionMasiva.confirmada(
      batchId: json['batch_id'] as String,
      modo: AppMode.fromStorage(json['mode']),
      cambios: (json['changes'] as List).map((raw) {
        final c = raw as Map<String, dynamic>;
        final supplier = c['supplier'] as Map<String, dynamic>?;
        final receipt = c['receipt'] as Map<String, dynamic>?;
        return CambioVarianteMasiva(
          clave: ClaveVariante(
            c['product_id'] as String,
            c['variant_id'] as String,
          ),
          baseProducto: _base(c['product_base'] as Map<String, dynamic>),
          venta: c['sale_minor'] == null
              ? const CambioExplicito.conservar()
              : CambioExplicito.establecer(c['sale_minor'] as int),
          oferta: c.containsKey('offer_minor')
              ? CambioExplicito.establecer(c['offer_minor'] as int?)
              : const CambioExplicito.conservar(),
          costo: c['cost_minor'] == null
              ? const CambioExplicito.conservar()
              : CambioExplicito.establecer(c['cost_minor'] as int),
          precioProveedor: supplier == null
              ? null
              : ProveedorVariante(
                  proveedorId: supplier['id'] as String,
                  precioInformadoMenor: supplier['price_minor'] as int,
                  fechaInformadaMs: supplier['quoted_at_ms'] as int,
                ),
          entrada: receipt == null ? null : _entrada(receipt),
        );
      }),
    );
  }
}

Map<String, Object?> _baseJson(BaseRevisionMasiva b) => {
  'id': b.id,
  'version': b.version,
  'event_id': b.eventId,
  'server_sequence': b.serverSequence,
};

BaseRevisionMasiva _base(Map<String, dynamic> j) => BaseRevisionMasiva(
  id: j['id'] as String,
  version: j['version'] as int,
  eventId: j['event_id'] as String?,
  serverSequence: j['server_sequence'] as int?,
);

Map<String, Object?> _entradaJson(EntradaMercanciaMasiva e) {
  final b = e.base;
  final u = b.unidad;
  return {
    'quantity_atomic': e.cantidadAtomic,
    'resource': _baseJson(b.recurso),
    'unit': {
      'id': u.id,
      'code': u.code,
      'name': u.nombre,
      'symbol': u.simbolo,
      'dimension': u.dimension.code,
      'factor': u.factorAtomico,
      'digits': u.maximosDecimales,
      'active': u.activa,
    },
    'balance_version': b.saldoVersion,
    'balance_event': b.saldoEventId,
    'balance_sequence': b.saldoServerSequence,
    'on_hand': b.existenciaAtomic,
    'available': b.disponibleAtomic,
  };
}

EntradaMercanciaMasiva _entrada(Map<String, dynamic> j) {
  final u = j['unit'] as Map<String, dynamic>;
  return EntradaMercanciaMasiva(
    cantidadAtomic: j['quantity_atomic'] as int,
    base: BaseEntradaMasiva(
      recurso: _base(j['resource'] as Map<String, dynamic>),
      unidad: UnidadInventario(
        id: u['id'] as String,
        code: u['code'] as String,
        nombre: u['name'] as String,
        simbolo: u['symbol'] as String,
        dimension: DimensionUnidad.fromCode(u['dimension'] as String),
        factorAtomico: u['factor'] as int,
        maximosDecimales: u['digits'] as int,
        activa: u['active'] as bool,
      ),
      saldoVersion: j['balance_version'] as int,
      saldoEventId: j['balance_event'] as String,
      saldoServerSequence: j['balance_sequence'] as int?,
      existenciaAtomic: j['on_hand'] as int,
      disponibleAtomic: j['available'] as int,
    ),
  );
}
