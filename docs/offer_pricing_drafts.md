# Motor de tarifa por borrador e interfaz de Caja (sesiones 4–5)

Caja cambia la tarifa con `VentaBorradorCommandService` mediante «Precio de oferta».
`EffectiveSalePrice.resolve` gobierna nuevas capturas y recálculo de snapshots.
Producción no está habilitada ni certificada por estas pruebas.

## Cambiar tarifa

Construir `CambiarTarifaVentaBorradorCommand` con `operationId` UUID estable,
`saleId`, `pricingMode` (`normal`/`offer`), `expectedVersion`,
`expectedDraftEventId` y `expectedTotalMinor`. La primera cabecera vacía usa
0/null/0 y un UUID nuevo no limpiado. Si la UI selecciona un UUID de pestaña,
usar ese mismo UUID.

`previewTarifa(command)` no escribe; devuelve before/after completos, totales,
`amountChangedLines`, `sourceOnlyChangedLines` y `withoutOfferLines`. Caja
presenta y confirma esa vista cuando hay líneas y conserva el comando
exacto al aceptar. Cancelar no llama `cambiarTarifa`. En vacío se puede llamar
inmediatamente. El modo destino debe diferir para pedir una vista previa.

`cambiarTarifa(command)` devuelve el payload original aplicado, o null si ya
coincide la tarifa y las condiciones. Evento ID = operationId. Ante pérdida de
respuesta, reusar la misma intención/UUID; no generar otro para el reintento.
La operación consulta el evento aplicado antes de validar la base. Reusar el
UUID con intención diferente falla, incluso si ya se cobró/limpió la venta.

La transacción SQLite incluye lectura, evento, refs, todas las líneas y cabecera.
Solo el evento nuevo usa temporalmente `application_status=failed` mientras se
aplica dentro de la transacción; se marca applied antes del commit. Un fallo
revierte también ese marcador. No existe un resultado visible parcialmente
aplicado, ni se añade tabla/esquema/migración por esta implementación.

`tarifa_venta_borrador_cambiada` permanece not_required en ambos modos. Los refs
sale/sale_item se declaran en ambos y solo se persisten en server_sync. No hay
endpoint remoto ni sincronización de borradores. El handler acredita replay por
identidad/intención en el diario; una versión vieja con otro UUID no basta.

## Captura y cobro

`prepararCaptura(variantId)` devuelve `SaleCaptureConditions` sin escritura.
`capture.measured` contiene precio efectivo, unidad/referencia y snapshots para
los diálogos. `capture.bind(command)` vincula la intención resultante a venta,
revisión, modo y evento de catálogo revisados. Agregar rechaza una guarda parcial
u obsoleta. Las llamadas directas sin guarda representan captura inmediata bajo
la transacción, sin un diálogo previo. No fabricar eventos de precio cuando falta
trazabilidad del catálogo: reparar/revisar el origen del producto.

Búsqueda manual y coordinador compartido HID/cámara usan este flujo; báscula y
captura por importe reciben sus condiciones desde él. Las vistas previas de
acumulación comparan también alternativas, origen y evento de precio.

La edición de cantidad conserva snapshots; alternar no fusiona líneas ni cambia
cantidad física, costo, receta o inventario. Desactivar restaura normal capturado.
Un borrador con líneas legadas puede cobrarse, incluso mezclado con v2, pero no
alternarse. Recapturar cotización es una captura nueva normal con catálogo actual;
el documento guardado anterior no se reescribe.

`VentaCommandService.confirmar` serializa con el mismo DAO. Conserva comprobación
de último evento y total; admite además `expectedVersion` para consumidores que
transportan la revisión completa. Un cambio de tarifa siempre avanza revisión y
último evento, aunque el total no cambie; el cobro viejo falla. La confirmación
emite contrato v2 y las dependencias de precio y consumo separadas. Los lectores
de borrador e historial transportan los metadatos; legado se expone unknown.
Ticket, reportes, pagos y ajustes calculan con el cobro histórico.

## Interfaz de Caja (sesión 5)

El botón observa `pricingMode` de la venta, sin estado optimista. Con líneas abre
`SalePricingReviewDialog` usando `previewTarifa`; al aceptar conserva comando,
UUID y base exactos. Vacía aplica inmediatamente. `_runAction` comparte la barrera
con cobro, pestañas, navegación y lector HID, que recupera el foco al terminar.
Un reintento sobre la misma intención conserva UUID; después de un resultado o
cambio de base se crea otra intención. Cancelar no escribe.

Las etiquetas usan `effectivePriceOrigin`: oferta aplicada, normal sin oferta
capturada o tarifa sin acreditar para legado. No deducen origen del total ni del
modo global. Errores vuelven a suscribirse a la lectura persistida conjunta.
Cobro lleva también `expectedVersion`; `SaleDraftChangedException` devuelve a
Caja para revisar el estado guardado. Otros errores conservan el formulario.

La capacidad sigue validándose en aplicación. El mensaje de incompatibilidad
pide verificar conexión/actualización del servidor, sin cambiar el modo guardado.
No se agregaron tablas, migraciones ni reglas de precio en widgets.

Pruebas: `test/presentation/pages/caja/offer_pricing_ui_test.dart` usa SQLite real
con fixtures, capacidades locales y entradas de hardware simuladas. Las rutas de
asignación/alta y pesaje se amplían en `physical_barcode_assignment_test.dart`.
La evidencia de S5 en el roadmap distingue pruebas automatizadas de hardware real.
Para capturas legibles, definir `POS_OFFER_VISUAL_DIR` y
`POS_OFFER_VISUAL_FONTS` (directorio del SDK Flutter que contiene
`Roboto-Regular.ttf` y `MaterialIcons-Regular.otf`) al ejecutar la prueba de UI.
Sin estas variables, los tests usan el entorno de fuentes habitual de Flutter.

## Continuación

Sesión 6: regresión integral, ensayo de respaldo/esquema/versiones instaladas,
terminales aisladas y preparación de piloto. Cámara, HID, báscula e impresión
físicos con esta tarifa siguen pendientes: los fakes verifican lógica/interfaz,
no compatibilidad física. No habilitar selección individual, consolidación ni
sincronización remota de borradores. No desplegar sin sus verificaciones.
