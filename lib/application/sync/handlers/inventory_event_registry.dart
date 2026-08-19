import '../event_handler.dart';
import '../payloads/recurso_inventario_creado_payload.dart';
import 'inventory_event_handler.dart';

Map<String, EventHandler> inventoryEventHandlers(
  InventoryEventHandler handler,
) => {
  RecursoInventarioCreadoPayload.eventType:
      handler.applyRecursoInventarioCreado,
};
