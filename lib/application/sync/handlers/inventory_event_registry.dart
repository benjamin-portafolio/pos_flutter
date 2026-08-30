import '../event_handler.dart';
import '../payloads/recurso_inventario_creado_payload.dart';
import '../payloads/recurso_inventario_actualizado_payload.dart';
import '../payloads/movimiento_inventario_registrado_payload.dart';
import 'inventory_event_handler.dart';

Map<String, EventHandler> inventoryEventHandlers(
  InventoryEventHandler handler,
) => {
  RecursoInventarioCreadoPayload.eventType:
      handler.applyRecursoInventarioCreado,
  RecursoInventarioActualizadoPayload.eventType:
      handler.applyRecursoInventarioActualizado,
  MovimientoInventarioRegistradoPayload.eventType:
      handler.applyMovimientoInventarioRegistrado,
};
