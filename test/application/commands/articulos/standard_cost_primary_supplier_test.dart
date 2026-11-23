import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/editar_articulo_comercial_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/base_revision_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_proveedor_precio.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_replenishment_patch.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';

import '../../../support/product_supplier_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    for (final path in ['editor', 'masiva', 'csv']) {
      for (final scenario in [
        'cambia',
        'cero',
        'sin captura',
        'igual',
        'sin costo',
        'sin principal',
        'cambia principal',
        'retira principal',
        'cotización igual',
      ]) {
        if (scenario == 'sin captura' && path != 'editor') continue;
        // La edición masiva solo admite costos con importe.
        if (path == 'masiva' && scenario == 'sin costo') continue;
        test('${mode.name}: $path / $scenario', () async {
          final h = ProductSupplierHarness(mode: mode);
          try {
            final principal = await h.supplier('Principal');
            final secundario = await h.supplier('Secundario');
            const oldDate = 100;
            final initialQuotes = [
              ProveedorVariante(
                proveedorId: principal,
                precioInformadoMenor: scenario == 'cotización igual'
                    ? 450
                    : 200,
                fechaInformadaMs: oldDate,
              ),
              ProveedorVariante(
                proveedorId: secundario,
                precioInformadoMenor: 900,
                fechaInformadaMs: oldDate,
              ),
            ];
            await h.commands.crearArticulo(
              CrearArticuloCommand.conVariantes(
                nombre: 'Producto',
                variantes: [
                  CrearArticuloVarianteCommand.conProveedores(
                    nombre: null,
                    precioVenta: '10',
                    costoEstandar: '3',
                    proveedores: initialQuotes,
                    currentSupplier: CambioExplicito.establecer(
                      scenario == 'sin principal' ? null : principal,
                    ),
                  ),
                ],
              ),
            );
            final id = h.appends.last.event.aggregateId;
            final product = (await h.tracking.products.findProductById(id))!;
            final before = await h.tracking.products.snapshot(id);
            final variant = before.variantes.single;
            final cost = switch (scenario) {
              'cero' => 0,
              'igual' => 300,
              'sin costo' => null,
              _ => 450,
            };
            final supplierChange = switch (scenario) {
              'cambia principal' => CambioExplicito<String?>.establecer(
                secundario,
              ),
              'retira principal' => const CambioExplicito<String?>.establecer(
                null,
              ),
              _ => const CambioExplicito<String?>.conservar(),
            };
            final replenishment = SupplierReplenishmentPatch.fromJson({
              if (supplierChange.establecer)
                'current_supplier_id': supplierChange.valor,
            });
            final eventCount = h.appends.length;
            final startMs = DateTime.now().millisecondsSinceEpoch;
            switch (path) {
              case 'editor':
                await h.commands.actualizarArticulo(
                  productId: id,
                  baseEventId: product.lastEventId!,
                  variantIds: [variant.id],
                  command: CrearArticuloCommand.conVariantes(
                    nombre: before.nombre,
                    variantes: [
                      CrearArticuloVarianteCommand.conProveedores(
                        nombre: null,
                        precioVenta: '10',
                        costoEstandar: cost == null
                            ? null
                            : (cost / 100).toString(),
                        proveedores: scenario == 'sin captura'
                            ? null
                            : initialQuotes,
                        currentSupplier: supplierChange,
                      ),
                    ],
                  ),
                );
              case 'masiva':
                final base = BaseRevisionMasiva(
                  id: id,
                  version: product.version,
                  eventId: product.lastEventId,
                  serverSequence: product.lastServerSequence,
                );
                await h.commands.editarArticuloComercial(
                  EditarArticuloComercialCommand(
                    productId: id,
                    base: base,
                    cambios: [
                      CambioVarianteMasiva(
                        clave: ClaveVariante(id, variant.id),
                        baseProducto: base,
                        venta: const CambioExplicito.conservar(),
                        costo: CambioExplicito.establecer(cost!),
                        precioProveedor: null,
                        entrada: null,
                        replenishment: replenishment,
                      ),
                    ],
                  ),
                );
              case 'csv':
                await h.commands.actualizarArticuloDesdeCsv(
                  ActualizarArticuloCsvCommand(
                    productId: id,
                    baseEventId: product.lastEventId!,
                    nombre: before.nombre,
                    categoriaId: before.categoriaId,
                    variantes: [
                      ActualizarArticuloVarianteCsvCommand(
                        variantId: variant.id,
                        nombre: variant.nombre,
                        precioVentaMinor: variant.precioVentaMenor,
                        precioCosteMinor: cost,
                        codigoBarras: variant.codigoBarras,
                        replenishment: replenishment,
                      ),
                    ],
                  ),
                );
            }
            final after = await h.tracking.products.snapshot(id);
            final updated = after.variantes.single;
            expect(updated.costoEstandarMenor, cost);
            expect(updated.precioVentaMenor, variant.precioVentaMenor);
            for (final quote in updated.proveedores!) {
              final original = variant.proveedores!.singleWhere(
                (q) => q.supplierId == quote.supplierId,
              );
              final changesPrice =
                  cost != null &&
                  cost != 300 &&
                  quote.supplierId == updated.replenishment.supplierId &&
                  original.quotedPriceMinor != cost;
              expect(
                quote.quotedPriceMinor,
                changesPrice ? cost : original.quotedPriceMinor,
              );
              if (changesPrice) {
                expect(quote.quotedAtMs, greaterThanOrEqualTo(startMs));
              } else {
                expect(quote.quotedAtMs, oldDate);
              }
            }
            if (scenario == 'igual') {
              expect(h.appends.length, eventCount);
            } else {
              expect(h.appends.length, eventCount + 1);
              final append = h.appends.last;
              final payload = ProductoActualizadoPayload.fromJson(
                append.event.payload,
              );
              expect(
                ProductoProveedorPrecio.sameList(
                  payload.after.variantes.single.proveedores,
                  updated.proveedores,
                ),
                isTrue,
              );
              expect(
                append.refs.any((r) => r.refType == 'variant_suppliers'),
                isTrue,
              );
            }
            expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
            if (mode == AppMode.standalone) {
              expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
              expect(
                (await h.tracking.storedEvents()).last.deliveryStatus,
                'not_required',
              );
            } else {
              expect(await h.db.select(h.db.eventRefs).get(), isNotEmpty);
              expect(
                (await h.tracking.storedEvents()).last.deliveryStatus,
                'pending',
              );
            }
          } finally {
            await h.dispose();
          }
        });
      }
    }
  }
}
