import '../commands/articulos/producto_command_service.dart';
import '../commands/inventario/inventory_command_service.dart';
import '../config/app_config.dart';
import '../sync/synced_event_history.dart';
import 'catalogo_edicion_masiva.dart';

/// Dependencias vinculadas por el adaptador a una única base, sin Drift en
/// aplicación. Su uso está limitado al callback transaccional del diario.
class UnidadTrabajoMasiva {
  const UnidadTrabajoMasiva({
    required this.modo,
    required this.catalogo,
    required this.productos,
    required this.inventario,
    required this.historial,
  });
  final AppMode modo;
  final CatalogoEdicionMasiva catalogo;
  final ProductoCommandService productos;
  final InventoryCommandService inventario;
  final SyncedEventHistory historial;
}
