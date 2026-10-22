# Alta de producto desde un código desconocido

Fecha: 2026-10-21.

Inventario por cámara y Caja por HID o cámara ofrecen «Dar de alta un producto»
junto a asignar a una variante existente y cancelar. El formulario habitual de
alta abre en modo avanzado con el código, incluidos sus ceros iniciales, en la
primera variante. Se puede editar antes de guardar. El guardado usa el comando
y el evento `producto_creado` existentes; no cambia el esquema.

Inventario vuelve al catálogo sin agregar líneas de venta. Caja continúa el
agregado sobre la misma venta persistida; solicita cantidad para artículos
medidos. Crear el producto y agregarlo son operaciones separadas: cancelar la
cantidad o fallar al agregar conserva el catálogo guardado. Si se cambia el
código y ya no resuelve al volver, se informa que quedó guardado sin agregar.
El lector HID conserva su pausa, cola y recuperación de foco; la cámara se
suspende durante el diálogo y el formulario.

Cobertura automatizada:

- `inventory_barcode_flow_test.dart`: alta con código `000987`, precio y
  persistencia real; fallo transaccional y reintento; cancelación sin escritura;
  venta previa sin nuevas líneas; regresiones de asignación y edición.
- `physical_barcode_assignment_test.dart`: alta desde HID con código precargado,
  persistencia, agregado a la venta previa y recuperación de foco; regresiones
  de asignación, interrupciones y cantidades.
- `sale_barcode_scanner_screen_test.dart`: oferta de opciones ante desconocidos,
  cancelación, cámara detenida durante interacciones y regresiones de lectura.
- `article_form_screen_test.dart`: regresiones del formulario y sus variantes.

La cámara simulada y los eventos de teclado no acreditan prueba física nueva
con cámara o lector HID. Se conservan los pendientes físicos documentados.

## Resultado de verificación

- `dart analyze`: sin observaciones.
- Ejecución final de las cuatro suites anteriores: **140 pruebas aprobadas**.
- `git diff --check`: sin errores.
- `flutter test` general: 2664 aprobadas, 24 omitidas y 75 fallidas. Incluye
  fixtures con rutas de macOS ausentes en Windows, bloqueos al eliminar SQLite,
  procesos no disponibles, comparación de impresión y timeouts de otras UI.
  Una expectativa del test nuevo sobre el mensaje del error inyectado se
  corrigió después de esa ejecución; su reejecución está incluida en las 140
  aprobadas. La suite general no se declara verde.

Los logs de esta sesión se conservan fuera del repositorio en
`%TEMP%/pos-barcode-creation-20261021` (`barcode-verified.log`,
`barcode-analyze-final.log` y `barcode-full-suite.log`).
