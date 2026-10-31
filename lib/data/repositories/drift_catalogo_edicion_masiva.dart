import 'package:drift/drift.dart';

import '../../application/edicion_masiva/base_entrada_masiva.dart';
import '../../application/edicion_masiva/base_revision_masiva.dart';
import '../../application/edicion_masiva/catalogo_edicion_masiva.dart';
import '../../application/edicion_masiva/clave_variante.dart';
import '../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../application/edicion_masiva/lectura_edicion_masiva.dart';
import '../../domain/articulos/proveedor_variante.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../local/drift/app_database.dart';

/// Lecturas por conjuntos en una transacción: sin eventos históricos, recetas
/// completas ni consultas de detalle por fila. No requiere nuevos DAOs/esquema.
class DriftCatalogoEdicionMasiva implements CatalogoEdicionMasiva {
  const DriftCatalogoEdicionMasiva(this.db);
  final AppDatabase db;

  @override
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  }) {
    if (limite < 1 || limite > 200 || desplazamiento < 0) {
      throw ArgumentError(
        'La página admite 1–200 filas y desplazamiento positivo.',
      );
    }
    return db.transaction(
      () => _filas(
        '(instr(lower(p.name), lower(?)) > 0 OR '
        'instr(lower(coalesce(v.name, \'\')), lower(?)) > 0)',
        [Variable(busqueda.trim()), Variable(busqueda.trim())],
        pagina: ' LIMIT $limite OFFSET $desplazamiento',
      ),
    );
  }

  @override
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  }) => db.transaction(() async {
    final filas = <ClaveVariante, FilaCatalogoMasivo>{};
    for (final grupo in _grupos(claves.map((k) => k.variantId).toSet())) {
      for (final fila in await _filas(
        'v.id IN (${List.filled(grupo.length, '?').join(',')})',
        grupo.map((id) => Variable(id)).toList(),
      )) {
        if (claves.contains(fila.clave)) filas[fila.clave] = fila;
      }
    }
    final activos = <String>{};
    for (final grupo in _grupos(proveedorIds)) {
      final rows = await (db.select(
        db.suppliers,
      )..where((s) => s.active.equals(true) & s.id.isIn(grupo))).get();
      activos.addAll(rows.map((s) => s.id));
    }
    return LecturaEdicionMasiva(filas: filas, proveedoresActivos: activos);
  });

  Future<List<FilaCatalogoMasivo>> _filas(
    String condicion,
    List<Variable<String>> variables, {
    String pagina = '',
  }) async {
    final rows = await db
        .customSelect(
          '$_select WHERE p.active = 1 AND '
          'v.active = 1 AND ($condicion) ORDER BY p.name, p.id, v.sort_order, v.id$pagina',
          variables: variables,
        )
        .get();
    final proveedores = <String, List<ProveedorVariante>>{};
    for (final grupo in _grupos(
      rows.map((r) => r.read<String>('variant_id')).toSet(),
    )) {
      for (final s in await (db.select(
        db.variantSuppliers,
      )..where((s) => s.variantId.isIn(grupo))).get()) {
        proveedores
            .putIfAbsent(s.variantId, () => [])
            .add(
              ProveedorVariante(
                proveedorId: s.supplierId,
                precioInformadoMenor: s.quotedPriceMinor,
                fechaInformadaMs: s.quotedAtMs,
              ),
            );
      }
    }
    return List.unmodifiable(
      rows.map((r) {
        final key = ClaveVariante(r.read('product_id'), r.read('variant_id'));
        final tieneReceta = r.read<int>('has_recipe') != 0;
        final resourceId = r.readNullable<String>('resource_id');
        final resourceActive = r.readNullable<int>('resource_active') == 1;
        final unit = _unidad(r, 'stock');
        final balanceEvent = r.readNullable<String>('balance_event');
        final impedimento = tieneReceta
            ? 'La variante usa receta. Gestiona sus recursos en Inventario.'
            : resourceId == null
            ? 'La variante no tiene seguimiento directo. Gestiona sus recursos en Inventario.'
            : !resourceActive ||
                  unit == null ||
                  !unit.activa ||
                  balanceEvent == null
            ? 'El recurso, su unidad o su saldo no están disponibles.'
            : null;
        return FilaCatalogoMasivo(
          clave: key,
          baseProducto: BaseRevisionMasiva(
            id: key.productId,
            version: r.read('product_version'),
            eventId: r.readNullable('product_event'),
            serverSequence: r.readNullable('product_sequence'),
          ),
          nombreProducto: r.read('product_name'),
          nombreVariante: r.readNullable('variant_name'),
          ventaMinor: r.read('sale_price_minor'),
          ofertaMinor: r.readNullable('offer_price_minor'),
          costoMinor: r.readNullable('standard_cost_minor'),
          configuracionVenta: r.read<String>('sale_mode') == 'unit'
              ? const UnitSaleConfiguration()
              : MeasuredSaleConfiguration(
                  saleUnitId: r.read('sale_unit_id'),
                  priceReferenceQuantityAtomic: r.read(
                    'price_reference_quantity_atomic',
                  ),
                ),
          unidadVenta: _unidad(r, 'sale'),
          impedimentoEntrada: impedimento,
          entrada: impedimento != null
              ? null
              : BaseEntradaMasiva(
                  recurso: BaseRevisionMasiva(
                    id: resourceId!,
                    version: r.read('resource_version'),
                    eventId: r.readNullable('resource_event'),
                    serverSequence: r.readNullable('resource_sequence'),
                  ),
                  unidad: unit!,
                  saldoVersion: r.read('balance_version'),
                  saldoEventId: balanceEvent!,
                  saldoServerSequence: r.readNullable('balance_sequence'),
                  existenciaAtomic: r.read('quantity_on_hand_atomic'),
                  disponibleAtomic: r.read('quantity_available_atomic'),
                ),
          proveedores: proveedores[key.variantId] ?? const [],
        );
      }),
    );
  }

  UnidadInventario? _unidad(QueryRow r, String prefix) {
    final id = r.readNullable<String>('${prefix}_unit');
    if (id == null) return null;
    return UnidadInventario(
      id: id,
      code: r.read('${prefix}_code'),
      nombre: r.read('${prefix}_name'),
      simbolo: r.read('${prefix}_symbol'),
      dimension: DimensionUnidad.fromCode(r.read('${prefix}_dimension')),
      factorAtomico: r.read('${prefix}_factor'),
      maximosDecimales: r.read('${prefix}_digits'),
      activa: r.read<int>('${prefix}_active') == 1,
    );
  }

  Iterable<List<String>> _grupos(Set<String> ids) sync* {
    final values = ids.toList();
    for (var i = 0; i < values.length; i += 400) {
      yield values.sublist(
        i,
        i + 400 > values.length ? values.length : i + 400,
      );
    }
  }

  static const _select = '''
SELECT p.id product_id, p.name product_name, p.version product_version,
 p.last_event_id product_event, p.last_server_sequence product_sequence,
 p.sale_mode, p.sale_unit_id, p.price_reference_quantity_atomic,
 v.id variant_id, v.name variant_name, v.sale_price_minor, v.offer_price_minor, v.standard_cost_minor,
 EXISTS(SELECT 1 FROM recipe_components c WHERE c.variant_id = v.id) has_recipe,
 i.id resource_id, i.active resource_active, i.version resource_version,
 i.last_event_id resource_event, i.last_server_sequence resource_sequence,
 b.version balance_version, b.last_event_id balance_event,
 b.last_server_sequence balance_sequence, b.quantity_on_hand_atomic, b.quantity_available_atomic,
 su.unit_id sale_unit, su.code sale_code, su.name sale_name, su.symbol sale_symbol,
 su.dimension sale_dimension, su.atomic_factor sale_factor,
 su.max_fraction_digits sale_digits, su.active sale_active,
 iu.unit_id stock_unit, iu.code stock_code, iu.name stock_name, iu.symbol stock_symbol,
 iu.dimension stock_dimension, iu.atomic_factor stock_factor,
 iu.max_fraction_digits stock_digits, iu.active stock_active
FROM products p JOIN product_variants v ON v.product_id = p.id
LEFT JOIN units su ON su.unit_id = p.sale_unit_id
LEFT JOIN inventory_items i ON i.id = v.inventory_item_id
LEFT JOIN units iu ON iu.unit_id = i.default_unit_id
LEFT JOIN inventory_balances b ON b.inventory_item_id = i.id
''';
}
