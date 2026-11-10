# Precio de oferta en catálogo — sesión 3

La variante conserva precio normal, oferta opcional y costo estándar independientes.
Oferta es un importe exacto positivo de hasta dos decimales, máximo
9007199254740991 centavos, menor o igual al normal. Bajar normal revalida la
oferta conservada; retirarla exige una intención explícita.

## Captura y eventos

El editor de variantes precarga oferta y muestra «Sin oferta» al estar vacío.
Guardar sin tocarla conserva; vaciar una oferta existente retira. El resultado y
sus copias retienen por separado el valor leído y `CambioExplicito<String?>`.
El formulario sencillo, barcode, proveedores, receta y seguimiento conservan el
campo al reconstruir snapshots completos. Editar solo oferta no mueve stock,
no cambia receta, costo ni la clave de consumo. Caja sigue usando precio normal.

`ProductoCommandService` relee la base dentro de la transacción y superpone la
intención. Promueve todas las variantes de una base legada al conocer oferta,
incluido null explícito; before/after mantienen presencia uniforme. El contrato
v2 tipado, handlers, proyección, base y undo de sesión 2 conservan el campo.
No se reescriben eventos anteriores. Undo restaura el respaldo exacto y no pisa
sucesores oficiales. Refs se declaran y validan en ambos modos, se persisten solo
en server_sync; standalone conserva not_required sin servicios de red.

## Edición masiva

La tarea «Precio de oferta» abre captura con Conservar, Establecer y Retirar.
Establecer vacío es un error. Cancelar no cambia la intención. La revisión incluye
antes/después y N1. Cambiar de vista conserva el borrador de oferta.
`CambioVarianteMasiva.oferta` es `CambioExplicito<int?>`; el diario v1 omite
`offer_minor` para conservar y lo incluye con null para retirar. Un diario viejo
omite la clave y conserva. Confirmación, reanudación y consulta del resultado
aplicado mantienen identidad e intención; el reintento no exige de nuevo la base
que ya cambió por su propia aplicación. No se agregan entradas de mercancía por
cambiar oferta.

## CSV

El formato actual de 14 columnas termina en `precio_oferta,eliminar_producto`.
El importe válido establece o actualiza oferta, el mismo importe es un no-op y
una celda vacía retira la oferta. En altas, vacío crea sin oferta. Una exportación
sin editar vuelve a entrar sin cambios, incluso si el historial legado desconoce
la oferta y la proyección no tiene una.

Se reconocen por encabezado exacto cuatro contratos: 10 columnas (altas), 12
(con IDs, sin oferta), 14 con `accion_oferta` (legado) y 14 con
`eliminar_producto` (actual). Los dos primeros conservan oferta existente. El
legado con acción conserva su interpretación original: vacío/conservar sin
importe conserva, establecer o acción vacía con importe establece, retirar sin
importe retira. Encabezados parciales, híbridos o reordenados son errores.

`eliminar_producto` admite `si`, `no` o vacío, recortando espacios y sin distinguir
mayúsculas. `si` requiere product_id existente; variant_id es opcional y, si se
informa, debe pertenecer al producto. Los campos comerciales de esa fila se
ignoran. Basta marcar una fila exportada; las demás pueden quedar intactas.
El grupo se rechaza si mezcla eliminación con cambios efectivos o intenta agregar
variantes. Omitir filas nunca elimina productos ni variantes.

La revisión y el diálogo muestran nombre, ID y todas las variantes activas del
producto completo que se eliminará. Al aplicar se reutiliza `eliminarArticulo`
y su evento `producto_actualizado` con `deleteProduct`, protección de base,
validación de referencias y desactivación histórica. El lote se revierte completo
ante cualquier error. No hay borrado SQL directo, cambios de esquema ni actividad
remota nueva.

No se acepta texto `null`, cero, exceso de decimales ni oferta superior al precio
normal. Todos los importes monetarios se leen sin redondeo silencioso.
Ejemplos y evidencia: [Verificación CSV](testing/csv_import_verification.md).

## Compatibilidad

`OfferPricingAvailability` usa la última capacidad acreditada del endpoint actual;
un endpoint desconocido/incompatible bloquea nuevas escrituras v2. El health
existente guarda capacidades; una captura offline puede usar el conocimiento ya
persistido. Ambas composiciones productivas de comandos (DI y diario masivo)
inyectan la misma comprobación. Standalone la omite sin acceder al store.
El push comprueba también `offer_pricing_v2` antes de enviar productos nuevos del
contrato. Recursos independientes pueden viajar antes que sus productos según
las dependencias existentes; carecer de capacidad no permite enviar el producto.

## Verificación y límites

Pruebas específicas en `offer_catalog_test.dart`, `offer_editor_test.dart`,
`offer_pricing_availability_test.dart` y `offer_catalog_server_test.dart`.
Las terminales de ensayo son SQLite separadas en disco con identidades ficticias,
contra NestJS/PostgreSQL en loopback. No son tablets físicas ni producción.
El respaldo instalado real, hardware y preparación de piloto siguen pendientes.
No cambian esquema SQLite 9, migraciones, motor de precios del borrador ni botón
de Caja. La evidencia y comandos exactos están en el roadmap del proyecto de
análisis, `Evidencia/sesion-3-2026-10-30/Verificacion sesion 3.md`.
