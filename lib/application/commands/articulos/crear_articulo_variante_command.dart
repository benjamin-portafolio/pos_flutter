import '../../../domain/articulos/proveedor_variante.dart';
import '../../edicion_masiva/cambio_explicito.dart';
import 'crear_articulo_recipe_component_command.dart';

class CrearArticuloVarianteCommand {
  const CrearArticuloVarianteCommand({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.codigoBarras,
    this.inventoryUnitId,
    this.initialStockQuantity,
    this.existingInventoryItemId,
    this.recipeComponents = const [],
    this.minimumStock = const CambioExplicito.conservar(),
  }) : proveedores = null;

  /// Variante con una captura completa e inmutable del conjunto de proveedores.
  /// El constructor const anterior conserva compatibilidad con comandos que
  /// desconocen el campo. null mantiene relaciones; [] es retirada explícita.
  CrearArticuloVarianteCommand.conProveedores({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.codigoBarras,
    this.inventoryUnitId,
    this.initialStockQuantity,
    this.existingInventoryItemId,
    this.recipeComponents = const [],
    this.minimumStock = const CambioExplicito.conservar(),
    List<ProveedorVariante>? proveedores,
  }) : proveedores = ProveedorVariante.canonical(proveedores);

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;

  /// Código de barras capturado; vacío significa variante sin código.
  final String? codigoBarras;

  /// Conservar por defecto; establecer cantidad en la unidad de inventario;
  /// establecer(null) retira explícitamente el mínimo. Requiere vínculo activo
  /// para cambiarlo; quitar seguimiento conserva el umbral dormido.
  final CambioExplicito<String?> minimumStock;
  final String? inventoryUnitId;
  final String? initialStockQuantity;

  /// Recurso de inventario existente que se quiere recuperar para esta variante.
  ///
  /// Es la única forma de resolver un legado ambiguo: la persona usuaria elige
  /// explícitamente entre candidatos compatibles. No crea un CRUD de recursos ni
  /// reemplaza al resolver por memoria; el command valida el identificador y lo
  /// somete a las mismas reglas que la memoria.
  final String? existingInventoryItemId;
  final List<CrearArticuloRecipeComponentCommand> recipeComponents;

  /// null conserva las relaciones actuales; [] retira explícitamente el conjunto.
  /// La captura es canónica e inmutable; el servicio valida existencia y base.
  final List<ProveedorVariante>? proveedores;
}
