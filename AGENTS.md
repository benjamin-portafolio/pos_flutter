# Guia para Codex en este proyecto

Este proyecto usa un flujo offline-first por eventos. Antes de implementar una funcionalidad similar a `crear espacio`, lee:

- `docs/architecture/offline_feature_flow.md`
- `docs/templates/new_offline_feature_checklist.md`

El analisis general del sistema se encuentra en:

- `/Users/benjamin/Library/CloudStorage/GoogleDrive-benjamin94833@gmail.com/My Drive/Projects/POS/analisis `

Nota: el nombre del directorio `analisis ` incluye un espacio final.

## Comunicacion con el usuario

- Cuando existan dudas, decisiones pendientes o solicitudes de confirmacion,
  presentarlas siempre como una lista numerada.

## Regla de alcance

- Implementa solo el agregado solicitado por el usuario.
- No agregues sincronizacion remota, push, pull, websocket o servidor si no se pide explicitamente.
- No agregues otro flujo de negocio si el usuario aun no lo ha analizado.
- Mantén los cambios pequenos y verificables.

## Flujo patron

```text
presentation
-> application/commands
-> crear SyncEvent
-> guardar events
-> guardar event_refs solo en server_sync
-> application/sync/EventProcessor.apply(event)
-> handler idempotente
-> tabla local/proyeccion
-> repository mapea Drift a dominio
-> presentation observa repository
```

## Carpetas

- `domain`: conceptos de negocio. No debe importar Drift ni SQLite.
- `application/commands`: comandos y command services que reciben intenciones de la UI.
- `application/sync`: `SyncEvent`, `EventProcessor` y handlers que aplican eventos.
- `data/local/drift`: tablas, DAOs y `AppDatabase`.
- `data/repositories`: adaptadores entre Drift y modelos de dominio.
- `presentation`: pantallas, dialogs y modelos propios de formularios.

## Convenciones

- Un resultado de formulario vive en `presentation`.
- Un comando de aplicacion vive en `application/commands`.
- Agrupar comandos y sus command services por funcionalidad dentro de
  `application/commands`: `categorias`, `espacios`, `articulos`, `inventario`
  y `ventas`. Mantener `LocalCommandContext` en la raiz como contexto compartido.
- Usar el sufijo `Command` para los datos que expresan una intencion de cambio
  y `CommandService` para el servicio que la procesa. Organizar sus tests con
  las mismas subcarpetas dentro de `test/application/commands`.
- Enums o conceptos de negocio viven en `domain`.
- Las tablas Drift y DAOs viven en `data/local/drift`.
- Toda tabla Drift debe incluir un comentario sobre su finalidad y documentar
  el uso de cada campo que declare.
- Los campos heredados deben estar documentados en su definicion comun; si una
  tabla les da un significado particular, aclararlo tambien en esa tabla.
- Las tablas Drift que necesiten identidad, estado y metadatos comunes de
  trazabilidad o sincronizacion deben heredar `CommonFields`; no redeclarar
  esos campos de forma individual.
- Si una tabla no puede usar `CommonFields`, documentar en la propia tabla la
  diferencia de modelo que justifica la excepcion.
- Los handlers de eventos deben ser idempotentes.
- `SyncEvent.payload` debe permanecer como `Map<String, Object?>` para
  transportar y persistir eventos heterogeneos; no convertir el sobre comun en
  `SyncEvent<T>`.
- Cada `event_type` implementado debe tener un contrato tipado en
  `application/sync/payloads`, con una clase principal por archivo,
  `aggregateType`, `eventType`, `fromJson` y `toJson`.
- Los command services deben construir el payload tipado y serializarlo con
  `toJson`; los handlers deben decodificar una vez con `fromJson` y usar despues
  solo campos tipados.
- Los registros, revalidadores y otros consumidores deben reutilizar las
  constantes y el contrato del payload; no duplicar literales ni interpretar
  manualmente campos especificos de `event.payload`.
- La compatibilidad con formatos legados debe ser explicita y estar cubierta
  por tests del contrato.
- `domain` no debe depender de `data`.
- La UI no debe insertar directo en Drift.
- Los comandos deben declarar y validar sus `LocalEventRef` en ambos modos.
- `DriftLocalEventStore` no debe persistir `event_refs` en modo `standalone`;
  esas filas son metadatos de preflight y conflictos de `server_sync`.
- Los eventos standalone deben conservar `delivery_status = not_required`.
- No habilitar push, pull, preflight, health checks o WebSocket en standalone.
- Si en el futuro se importa historial standalone a servidor, definir un flujo
  explicito que reconstruya referencias; no cambiar silenciosamente esta regla.

## Organizacion de clases por archivo

- Usar una clase principal por archivo como regla base.
- Se pueden mantener varias clases en un archivo cuando sean auxiliares,
  pequenas, privadas del archivo y solo tengan sentido junto a la clase
  principal.
- En Flutter/Dart, es valido agrupar widgets privados como
  `_ProductHeader` o `_ProductActions` si solo los usa la pantalla o widget
  principal de ese archivo.
- Separar una clase a su propio archivo cuando crezca, se importe desde otros
  modulos, se testee por separado, represente una responsabilidad importante o
  pertenezca a otra capa.
- Si una clase merece ser buscada, importada, testeada o entendida por
  separado, debe tener su propio archivo.

## Validaciones por agregado

En desarrollos offline-first similares a `crear espacio`, aplicar validaciones
solo cuando correspondan al agregado solicitado.

- En el command service, normalizar entradas antes de crear el `SyncEvent`:
  - `trim` para textos.
  - rechazar campos obligatorios vacios.
  - convertir campos opcionales vacios a `null`.
- En handlers, mantener idempotencia y proteger invariantes locales evidentes
  del agregado, como identificadores unicos.
- En Drift, usar constraints o indices locales solo para invariantes reales del
  agregado.
- Agregar tests enfocados para normalizacion, campos requeridos, duplicados e
  idempotencia cuando esos casos apliquen.
- No agregar validaciones especulativas ni reglas de negocio no solicitadas.

## Esquema Drift durante desarrollo

- Hasta que el usuario indique lo contrario, cada cambio de esquema local debe
  asumir reinicio de base de datos y perdida de datos locales.
- No agregar migraciones `onUpgrade` ni subir `schemaVersion` para cada cambio
  de esquema local.
- Mantener `schemaVersion` fijo aunque Drift lo requiera.
- Usar `_resetDatabaseOnStartup` para recrear la base con el esquema actual.
- Despues de cambios en tablas Drift, ejecutar `dart run build_runner build`
  para regenerar el esquema.

## Limpieza posterior a cambios

- Despues de cada cambio, revisar si quedaron imports, metodos, clases, archivos, dependencias o helpers sin uso.
- Eliminar codigo muerto o estructura futura que no tenga un proposito actual.
- No dejar placeholders ni extensiones pendientes salvo que el usuario lo pida explicitamente.
- Si se conserva algo sin uso directo porque fue solicitado como estructura pendiente, mencionarlo en la respuesta final.
- Usar `dart analyze` y busquedas con `rg` cuando ayuden a confirmar que no quedan referencias rotas o piezas sin usar.

## Verificacion minima

Despues de cambios de tablas Drift:

```sh
dart run build_runner build
```

Despues de cualquier cambio funcional:

```sh
dart analyze
flutter test
```

## Estado actual

El flujo completo implementado como referencia es `espacio_creado`.
El boton `Agregar mesa` existe visualmente, pero no tiene flujo funcional por decision de alcance.
El boton `ESCANEAR` del editor de variantes navega a `BarcodeScannerScreen`, que
usa la camara con `mobile_scanner` y devuelve un `String` con el codigo leido,
o `null` si el usuario cancela. El editor valida y llena el campo; el guardado
conserva el mismo flujo que la captura manual. La pantalla acepta una sola
lectura y libera la camara al cerrar o pasar la app a segundo plano, incluso
si habia una solicitud de permiso pendiente. Android usa el detector incluido
para funcionar offline; iOS y macOS declaran el uso de camara y macOS incluye
el entitlement correspondiente.
Los dos accesos de codigo de barras de Caja abren `SaleBarcodeScannerScreen`,
con escaneo continuo, `BarcodeReadGate` y la misma venta persistida que Caja.
El lector fisico de Caja ofrece asignar codigos desconocidos a una variante
existente y agregarla a la misma venta. Reutiliza el selector y la confirmacion
de Inventario, pausa la admision durante el recorrido y conserva la cola.
Guardar el codigo y agregar a la venta son operaciones separadas: cancelar
cantidad o fallar al agregar conserva el codigo y lo informa, sin reintento
automatico. La camara de Caja tambien ofrece asignacion y alta para codigos
desconocidos, suspendiendo la camara durante el recorrido. Verificacion:
`test/presentation/pages/caja/physical_barcode_assignment_test.dart`.
La compuerta temporal conserva pruebas fisicas pendientes de retirada/enfoque;
no bloquean la integracion (plan de Escaneo en caja, revision 2).
`ArticleSearchBar` recibe `onScanBarcode` opcional. Articulos no lo proporciona
y conserva su lector deshabilitado y su busqueda textual.
Gestion del inventario ofrece un lector sobre `+` solo en Articulos. Reutiliza
`BarcodeScannerScreen`: una coincidencia abre edicion y destaca la variante;
varias requieren elegir; sin coincidencias ofrece seleccionar una variante y
confirmar asignacion o reemplazo. El comando `AsignarCodigoBarrasVarianteCommand`
guarda solo ese barcode mediante `producto_actualizado`, con la base confirmada.
No agrega lineas de venta ni movimientos. La verificacion automatizada I01-I19
esta cerrada; la prueba fisica I20 sigue pendiente por decision del usuario.
Evidencia y limites: `docs/testing/inventory_barcode_verification.md`.
Los codigos desconocidos de Inventario y Caja (HID/camara) ofrecen ademas
«Dar de alta un producto». Abre el formulario habitual de alta avanzada con el
codigo precargado en la primera variante; guarda por `producto_creado`.
Inventario vuelve al catalogo; Caja continua el agregado a la misma venta,
separado del alta. Cancelar el alta no crea el producto; cancelar cantidad o
fallar al agregar conserva el producto ya guardado. Evidencia:
`docs/testing/unknown_barcode_product_creation.md`.

Basculas en Windows ofrece perfiles locales, predeterminada opcional y prueba
exclusiva para Rhino BAR-8RS. El acceso HID de Caja abre pesaje solo para masa
kg/g con predeterminada; camara, captura manual, piezas, volumen, buscador y
edicion conservan sus recorridos. El peso confirmado usa el comando/evento de
borrador existente, sin cambios de esquema ni sincronizacion. La sesion 5
verifica analisis, regresiones y build; con Rhino real y teclado manual verifica
configuracion/reinicio, boton/Enter, acumulacion y ticket de prueba 700 g/$35.00,
cancelacion, desconexion/silencio, recuperacion explicita y foco/segundo plano.
Conserva HID fisico/cola pendientes (lector sin entrada), limites B04/B15 y suite
global Windows no verde. Los datos del ensayo estan aislados de los del usuario.
No declarar cierre ni compatibilidad fisica completa por los fakes/build.
Resultados, revision y punto de reanudacion:
`docs/testing/weighing_windows_verification.md` y evidencia S5 del plan del vault.
