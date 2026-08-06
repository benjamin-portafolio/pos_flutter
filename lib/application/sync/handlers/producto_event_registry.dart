import '../event_handler.dart';
import '../payloads/producto_creado_payload.dart';
import 'producto_event_handler.dart';

Map<String, EventHandler> productoEventHandlers(ProductoEventHandler handler) =>
    {ProductoCreadoPayload.eventType: handler.applyProductoCreado};
