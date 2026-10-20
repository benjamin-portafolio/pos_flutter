# Pestañas de ventas en Caja

Implementado el 2026-10-20. Caja muestra dos pestañas iniciales y `+` agrega y
selecciona otra. Cada pestaña identifica un borrador independiente del mismo
usuario y dispositivo. Buscar, editar cantidades, eliminar líneas, escanear,
cotizar, limpiar y cobrar trabajan sobre la selección actual. Los comandos
capturan la selección antes de esperar la transacción. El cambio de pestaña
espera la barrera existente del lector físico y después restaura el lector.

Las pestañas vacías no generan eventos. Agregar el primer artículo persiste la
compra con los eventos locales existentes; se mantienen `not_required` y las
reglas de referencias de standalone/server_sync. Limpiar o cobrar sustituye la
identidad de esa pestaña por una captura vacía, sin cambiar otras compras.
Al abrir Caja se recuperan todos los borradores pendientes, por orden de creación.
La selección y las pestañas sin captura son estado de sesión; no se guardan
como eventos de negocio. PageStorage conserva el orden, la selección y las
pestañas vacías al salir de Caja y regresar durante la misma sesión.
No se añadieron operaciones remotas.

La recuperación de cotizaciones conserva sus reglas actuales. Continuar una
cotización selecciona su venta vinculada en Caja. Recuperar una nueva sigue
requiriendo resolver las otras capturas, conforme a su contrato existente.

El esquema reemplaza `ux_sales_local_draft` por el índice no único
`ix_sales_local_drafts`. Se mantiene schemaVersion. Conforme a AGENTS.md, el
arranque recrea una base de desarrollo con el índice anterior; no se añadió
migración. No se abrió la base real de la instalación para verificar el cambio.

## Cobertura automatizada

- `venta_borrador_command_service_test.dart`: dos capturas del mismo usuario y
  dispositivo, selección capturada antes de la espera, cantidades independientes,
  edición y eliminación de líneas, limpieza, rechazo de identidades limpiadas,
  ajenas o confirmadas, y reglas locales en ambos modos.
- `venta_command_service_test.dart`: cobrar la compra rápida conserva la otra
  revisión y genera pago y consumo sólo para la venta confirmada, en ambos modos.
- `caja_tabs_test.dart`: pestañas iniciales, agregar, búsqueda, limpieza, destino
  del cobro, barrera del lector físico y lectura posterior en la nueva pestaña;
  orden y selección al volver a Caja; recuperación de tres compras desde un
  archivo SQLite tras reiniciar.
- `caja_screen_test.dart`: presentación en teléfono estrecho con texto ampliado.
- `sale_draft_tabs_schema_test.dart`: recreación del esquema anterior y
  conservación de varios borradores entre reinicios con el esquema actual.

Las pruebas físicas de cámara y lector quedan fuera de esta verificación automatizada.

## Resultados ejecutados

- `dart run build_runner build`: esquema regenerado correctamente.
- `dart analyze`: sin incidencias.
- Pruebas focalizadas de Caja y confirmación de ventas: 67 aprobadas.
- Pruebas finales de navegación de pestañas, esquema y el archivo completo
  `recepcion_reapertura_test.dart`: 22 aprobadas.
- `flutter test --concurrency=4 --reporter expanded`: 2553 aprobadas,
  23 omitidas por sus requisitos de integración y un timeout de 30 segundos
  en `recepcion_reapertura_test.dart`, caso `M33 esquema sin tabla,
  protegido=false`. La primera ejecución con concurrencia predeterminada
  también agotó el tiempo en ese archivo, en el caso standalone M32.
  El archivo pasó completo al ejecutarlo por separado junto a las pruebas
  nuevas de pestañas y esquema. La suite completa no quedó verde.
