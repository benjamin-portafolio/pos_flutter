import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:pos_flutter/domain/articulos/variante_detalle.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_preview_form.dart';

void main() {
  test('conserva venta medida, costos, seguimiento y cantidades de receta', () {
    const unit = UnidadInventario(
      id: 'kg',
      code: 'kg',
      nombre: 'Kilogramo',
      simbolo: 'kg',
      dimension: DimensionUnidad.mass,
      factorAtomico: 1000,
      maximosDecimales: 3,
      activa: true,
    );
    const resource = RecursoInventarioListado(
      id: 'resource',
      nombre: 'Harina',
      activo: true,
      existenciaAtomica: 7000,
      unidadPredeterminada: unit,
    );
    final configuration = MeasuredSaleConfiguration(
      saleUnitId: 'kg',
      priceReferenceQuantityAtomic: 1000,
    );
    final result = ArticuloPreviewForm.fromDetalle(
      ArticuloDetalle(
        nombre: 'Pan',
        categoriaId: null,
        saleConfiguration: configuration,
        variantes: const [
          VarianteDetalle(
            nombre: null,
            precioVentaMenor: 1001,
            costoEstandarMenor: 0,
            inventoryItemId: 'resource',
            componentesReceta: {},
          ),
          VarianteDetalle(
            nombre: 'Especial',
            precioVentaMenor: 2000,
            costoEstandarMenor: null,
            inventoryItemId: null,
            componentesReceta: {'resource': 125},
          ),
        ],
      ),
      [resource],
    );
    expect(result.saleConfiguration, configuration);
    expect(result.variantes.first.precioVenta, '10.01');
    expect(result.variantes.first.costoEstandar, '0.00');
    expect(result.variantes.first.inventoryUnitId, 'kg');
    expect(result.variantes.first.existenciaInicial, isNull);
    expect(result.variantes.last.costoEstandar, isNull);
    expect(result.variantes.last.recipeComponents.single.quantity, '0.125');
    expect(
      result.variantes.last.recipeComponents.single.resource.nombre,
      'Harina',
    );
  });
}
