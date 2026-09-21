# Patron para funcionalidades offline-first

Esta guia describe como agregar una funcionalidad local basada en eventos, usando el flujo actual de `espacio_creado` como modelo.

## Objetivo

Cada accion de negocio debe poder ejecutarse localmente sin depender del servidor. La accion se guarda como evento pendiente y se aplica a una tabla local de lectura. La sincronizacion remota queda fuera del flujo salvo que se solicite explicitamente.

## Flujo

```text
UI
  -> FormResult de presentation
  -> Command de application
  -> CommandService
  -> construir payload tipado
  -> crear SyncEvent
  -> LocalEventStore.appendAndApply(event, refs)
  -> guardar events con delivery_status segun modo
  -> guardar event_refs solo en server_sync
  -> EventProcessor.apply(event)
  -> EventHandler decodifica payload tipado
  -> EventHandler idempotente
  -> actualizar tabla Drift local
  -> Repository mapea Drift a modelo de dominio
  -> UI observa Repository
```

## Responsabilidades por capa

`presentation`

- Muestra formularios y pantallas.
- Puede tener `FormResult` para datos crudos del formulario.
- Llama a command services.
- No escribe directamente en Drift.
- Debe asumir que las funcionalidades se incorporan de forma incremental.
- La pantalla principal coordina la navegacion y los casos de uso, mientras
  menus, formularios, selectores y widgets con responsabilidad propia viven en
  archivos separados. No concentrar en una sola pantalla codigo de funciones
  actuales y futuras que deban evolucionar de manera independiente.

`domain`

- Contiene modelos, enums y reglas de negocio.
- No importa `data/local/drift` ni clases generadas por Drift.
- No conoce detalles de SQLite.

`application/commands`

- Agrupa comandos y command services en subcarpetas por funcionalidad:
  `categorias`, `espacios`, `articulos`, `inventario` y `ventas`.
- Cada `Command` contiene los datos de una intencion de cambio; el
  `CommandService` correspondiente coordina su ejecucion. Ambos viven juntos
  dentro de la subcarpeta de su funcionalidad, en archivos separados.
- Mantiene `LocalCommandContext` en la raiz por ser compartido entre servicios.
- Convierte una intencion de negocio en uno o mas eventos.
- Construye el payload tipado del evento y lo serializa con `toJson`.
- Declara las referencias de negocio que necesita el evento.
- Delega el guardado transaccional y la aplicacion local a `LocalEventStore`.
- Usa `LocalCommandContext` para `deviceId` y `userId`.

`application/sync`

- Contiene `SyncEvent`.
- Contiene el puerto `LocalEventStore` y el modelo `LocalEventRef`.
- Contiene puertos de persistencia/proyeccion usados por sync local y remota.
- Contiene `SyncProjection`, la base de campos comunes para DTOs de
  proyeccion usados por handlers.
- Contiene `EventProcessor`.
- Contiene los contratos tipados de payload en `application/sync/payloads`.
- Contiene handlers que aplican eventos a proyecciones locales.
- Cada handler decodifica el payload con el contrato correspondiente antes de
  aplicar reglas o modificar la proyeccion.
- Los handlers dependen de puertos de proyeccion, no de Drift.
- Los handlers deben ser idempotentes.

`data/local/drift`

- Define tablas, DAOs y base local.
- Cada tabla debe documentar su finalidad y el uso de todas las columnas que
  declare. Los campos heredados se documentan en su definicion comun; cualquier
  significado adicional propio del agregado se aclara en la tabla concreta.
- Durante desarrollo, los cambios de esquema local reinician la base con
  `_resetDatabaseOnStartup`; no agregar migraciones `onUpgrade` ni subir
  `schemaVersion` salvo que el usuario lo pida.
- Implementa `LocalEventStore` ocultando `EventsCompanion`, `EventRefsCompanion`
  y transacciones.
- Implementa los puertos de `application/sync` usando Drift.
- No debe contener logica de UI.

`data/repositories`

- Adapta datos Drift a modelos de dominio.
- Es el borde entre persistencia y lectura de la app.

## Archivos de referencia

```text
lib/domain/espacios/espacio.dart
lib/domain/espacios/visibilidad_espacio.dart
lib/application/commands/espacios/crear_espacio_command.dart
lib/application/commands/espacios/espacio_command_service.dart
lib/application/sync/models/sync_event.dart
lib/application/sync/payloads/espacio_creado_payload.dart
lib/application/sync/payloads/categoria_creada_payload.dart
lib/application/sync/payloads/categoria_actualizada_payload.dart
lib/application/sync/payloads/categoria_movida_payload.dart
lib/application/sync/local_event_store.dart
lib/application/sync/event_processor.dart
lib/application/sync/handlers/espacio_event_handler.dart
lib/application/sync/projections/sync_projection.dart
lib/data/local/drift/drift_local_event_store.dart
lib/data/local/drift/tables/espacios.dart
lib/data/local/drift/tables/events.dart
lib/data/local/drift/tables/event_refs.dart
lib/data/local/drift/daos/espacio_dao.dart
lib/data/repositories/espacio_repository_impl.dart
lib/domain/repositories/espacio_repository.dart
```

## Contratos tipados de payload

`SyncEvent` conserva `payload` como `Map<String, Object?>` porque una pagina de
pull, la tabla `events` y el procesador contienen eventos heterogeneos. No se
debe convertir el sobre comun en `SyncEvent<T>`.

Cada `event_type` implementado debe tener un contrato de payload con una clase
principal en su propio archivo dentro de `application/sync/payloads`. El
contrato debe:

- Declarar las constantes `aggregateType` y `eventType`.
- Exponer campos tipados con los datos propios del evento.
- Implementar `fromJson` para validar y normalizar datos locales o remotos.
- Implementar `toJson` para producir la representacion canonica persistida y
  enviada al servidor.
- Aceptar formatos legados solo cuando la compatibilidad sea intencional y
  este probada.
- Ignorar campos adicionales desconocidos para permitir evolucion compatible,
  pero rechazar tipos o valores invalidos en los campos conocidos.

El flujo local usa el mismo contrato que el pull:

```text
CommandService
  -> validar conceptos de dominio
  -> construir XPayload
  -> XPayload.toJson()
  -> SyncEvent.payload

SyncEvent.fromJson()
  -> EventProcessor selecciona handler por eventType
  -> handler llama XPayload.fromJson(event.payload)
  -> handler usa solo campos tipados
  -> proyeccion local
```

El registro del evento y el command service deben usar las constantes del
contrato en vez de repetir literales. Otros consumidores que necesiten campos
especificos, como la revalidacion de pendientes, tambien deben decodificar el
mismo contrato; no deben volver a interpretar el mapa manualmente.

Contratos existentes:

| Evento | Contrato | Campos |
|---|---|---|
| `espacio_creado` | `EspacioCreadoPayload` | `nombre`, `identificacion`, `visibilidad` |
| `categoria_creada` | `CategoriaCreadaPayload` | `name`, `color_key`, `sort_order` |
| `categoria_actualizada` | `CategoriaActualizadaPayload` | `base_event_id`, `changed_fields`, `changes` |
| `categoria_movida` | `CategoriaMovidaPayload` | bases y cambios de `sort_order` de dos categorias |
| `producto_creado` | `ProductoCreadoPayload` | `product`, una variante sencilla y dependencias locales opcionales |

`producto_creado` conserva `product.category_id` y una referencia `category`
con relacion `uses` cuando el articulo pertenece a una categoria. Una categoria
oficial no agrega una base de estado al payload: cambios de nombre, color u
orden no son antecedentes de la creación del producto. Si la categoria fue
creada localmente y `categoria_creada` sigue pendiente, el payload declara
solamente `depends_on_event_id` para diferir el push hasta entregar esa
creacion. El lector mantiene compatibilidad explicita con el formato legado de
`base_event_id`, `base_version` y `base_server_sequence`.

`categoria_actualizada` transporta solo cambios de `name` y `color_key`. Cada
entrada de `changes` conserva los valores `from` y `to`; `base_event_id`
identifica el ultimo evento conocido al iniciar la edicion. El sobre tambien
debe incluir `base_version` y, cuando exista estado oficial, la
`base_server_sequence`.

`categoria_movida` intercambia las posiciones consecutivas de la categoria
principal y otra categoria desplazada. El payload conserva `from` y `to`, el
evento base, la version y la secuencia oficial conocidas para ambas. El evento
declara una referencia `affects` por cada categoria y el handler actualiza las
dos proyecciones dentro de la misma transaccion.

Un payload invalido recibido por pull hace fallar su aplicacion. Como los
eventos de la pagina y el checkpoint se procesan en una misma transaccion, la
pagina no debe quedar aplicada parcialmente ni avanzar el cursor.

## Proyecciones y campos comunes

Las tablas Drift que representan proyecciones locales y necesitan identidad,
estado y metadatos de trazabilidad o sincronizacion deben heredar
`CommonFields`: `id`, `active`, `version`, `createdEventId`, `lastEventId` y
`lastServerSequence`. Estos campos no deben redeclararse individualmente en
cada tabla.

Antes de crear una tabla se debe evaluar si representa una proyeccion sujeta al
flujo de eventos. Si necesita solo una parte de los campos comunes o su modelo
es incompatible con `CommonFields`, la excepcion debe justificarse en los
comentarios de la tabla y en la documentacion del agregado; no se debe duplicar
silenciosamente la estructura comun.

En `application/sync` no se debe importar `CommonFields` ni clases generadas por
Drift. Para mantener el mismo concepto sin acoplar capas, los DTOs de
proyeccion que usan los handlers deben extender `SyncProjection` y agregar solo
los campos especificos del agregado.

Ejemplo:

```text
Espacios extends Table with CommonFields
EspacioProjection extends SyncProjection
```

El adaptador Drift, por ejemplo `DriftEspacioProjectionStore`, es el encargado
de mapear entre la fila Drift y el DTO de proyeccion de `application/sync`.

## Event refs

Cada comando debe declarar al menos una referencia al agregado principal:

```text
ref_type: <agregado>
ref_id: <aggregate_id>
relationship: affects
source: local_pending
```

Si el evento usa una clave de negocio que debe validarse o ser unica, agregar otra referencia:

```text
ref_type: <agregado>_<clave>
ref_id: <valor>
relationship: requires_unique
source: local_pending
```

La declaracion y validacion de `LocalEventRef` es comun a ambos modos para que
los command services no dependan de la configuracion de despliegue. La
persistencia difiere:

- En `server_sync`, `DriftLocalEventStore` guarda las referencias porque
  preflight y el reporte de conflictos las necesitan.
- En `standalone`, guarda el evento con `delivery_status = not_required`, aplica
  la proyeccion local y omite la insercion en `event_refs`.

No interpretar la ausencia de referencias persistidas en standalone como falta
de trazabilidad: `events.aggregate_type`, `events.aggregate_id` y los campos de
evento/proyeccion mantienen la trazabilidad local. Una futura importacion de
historial standalone a servidor debe reconstruir referencias de manera
explicita; no debe convertir automaticamente esos eventos en pendientes.

## Idempotencia

Un handler debe soportar que llegue el mismo evento mas de una vez.

Para un evento `*_creado`:

- Si el registro no existe, insertarlo.
- Si existe y `createdEventId` coincide con el evento, ignorarlo.
- Si existe y `createdEventId` no coincide, fallar o marcar conflicto segun la regla del agregado.

### Confirmaciones o ecos del servidor

Esta regla se aplica a todos los tipos de evento, no solo a un agregado:

- Antes de guardar un evento recibido del servidor,
  `DriftSyncedEventStore` consulta por `event_id` dentro de la misma
  transaccion.
- Si el evento ya existe localmente con `application_status = applied`, la
  copia remota es una confirmacion o eco. Se actualizan el estado y los
  metadatos de sincronizacion del evento (`delivery_status`,
  `server_sequence`, `created_at_server` y motivo cuando corresponda), junto
  con la secuencia y el origen de sus `event_refs`. Para los eventos de
  categoria implementados, un reconocedor de ecos avanza tambien
  `lastServerSequence` en las proyecciones afectadas sin modificar sus campos
  de negocio, `version` ni `lastEventId`; no se vuelve a llamar a
  `EventProcessor`.
- La decision no depende de `lastEventId` de la proyeccion. Esa proyeccion
  puede haber avanzado por eventos locales posteriores y reaplicar el eco
  podria sobrescribirlos.
- Si el `event_id` no existe o su `application_status` no es `applied`, se
  conserva el flujo remoto normal: guardar el evento y aplicarlo mediante
  `EventProcessor`.

La deteccion, la actualizacion de metadata y la aplicacion cuando corresponda
deben permanecer en una sola transaccion. La idempotencia propia de cada
handler sigue siendo necesaria para eventos remotos nuevos y para otros
contextos de aplicacion.

### Dependencias causales entre eventos locales

Cuando `base_event_id` referencia otro evento local con
`delivery_status = pending`, el evento dependiente ya esta aplicado en la
proyeccion optimista, pero todavia no debe incluirse en el mismo push que su
base. Primero se envia la raiz de la cadena y el dependiente permanece
`pending`.

Al confirmarse la base, la revalidacion resuelve su `server_sequence` mediante
`base_event_id` y la usa como base oficial efectiva. Esto evita comparar el
dependiente contra una secuencia anterior conservada en la proyeccion y evita
clasificar el eco de su propia base como un cambio concurrente.

```text
A pending -> B se aplica localmente y espera el push
A delivered(server_sequence = N) -> B se revalida desde N y puede enviarse
A conflict -> B tambien entra en conflict
```

Si una base entra en conflicto, sus dependientes se reclasifican en la misma
operacion y las proyecciones se restauran desde el ultimo evento hacia el
primero. El servicio que reporta esos conflictos al servidor solo completa
metadatos; no vuelve a restaurar una proyeccion ya corregida.

## Lo que no debe hacerse

- No guardar directo desde UI a una tabla Drift.
- No poner enums de negocio en modelos de formulario.
- No hacer que `domain` importe `data`.
- No hacer que `application` importe `data/local/drift`; usar puertos.
- No hacer que una proyeccion de `application/sync` dependa de `CommonFields`;
  usar `SyncProjection`.
- No leer repetidamente campos especificos desde `event.payload` fuera del
  contrato tipado del evento.
- No duplicar literales de `aggregate_type` o `event_type` cuando el contrato
  ya expone sus constantes.
- No mezclar varios agregados si el usuario pidio analizar solo uno.
- No implementar sync remota como efecto colateral de un flujo local.

## Verificacion

Si cambian tablas o DAOs Drift:

```sh
dart run build_runner build
```

Siempre:

```sh
dart analyze
flutter test
```

## Organización de ProductoCommandService

En `lib/application/commands/articulos/producto_command_service.dart`, los métodos
`crearArticulo` y `actualizarArticulo` construyen explícitamente sus respectivos
eventos. La edición carga y valida su base antes de preparar el nuevo estado.

La preparación compartida se distribuye en métodos privados:

- `_prepareArticulo`: coordina la preparación y construye el payload de producto.
- `_normalizeVariants` y `_resolveVariantIds`: validan los datos y las identidades de variantes.
- `_prepareInventoryBindings` y `_resolveInventoryDependencies`: preparan los recursos nuevos y las dependencias de inventario.
- `_buildVariantPayloads`: construye las variantes del payload.
- `_buildArticleRefs`: declara las referencias del producto, variantes, recetas, categoría, inventario y unidad cuando corresponden.
- `_appendArticulo`: arma el lote con los recursos nuevos antes del evento de producto y lo entrega a `appendAndApplyAll`.

El producto y todas sus variantes siguen viajando en un solo evento de producto.
Drift guarda y aplica el lote completo en una misma transacción local.

## Organización de otros comandos y de la revalidación

- `CategoriaCommandService.eliminarCategoria` coordina la preparación del borrado,
  la creación del evento y su aplicación. Métodos privados validan los artículos
  confirmados, resuelven su destino, calculan el reordenamiento y construyen las
  referencias. El handler conserva la validación final dentro de la transacción.
- `InventoryCommandService.editarRecurso` prepara por separado el cambio de nombre
  y el movimiento. Si hay ambos, el movimiento usa el evento del cambio de nombre
  como base, incrementa la versión y espera su entrega antes del push. El lote
  sigue guardándose y aplicándose atómicamente.
- `VentaBorradorCommandService.agregar` separa la captura del artículo, la cantidad
  medida, la agrupación con una línea compatible y las referencias. Todo sigue
  ejecutándose dentro de `store.atomic` y el evento conserva `not_required`.
- `SyncPushService` separa el estado efectivo de la respuesta, su persistencia y
  la propagación de conflictos a los eventos en espera. Un duplicado conserva el
  estado original informado por el servidor. La actualización de estados y refs
  y la restauración inversa de proyecciones comparten una transacción.

`PendingEventRevalidator` coordina los validadores de
`lib/application/sync/revalidation`: `EspacioPendingEventValidator`,
`CategoriaPendingEventValidator`, `ProductoPendingEventValidator` e
`InventoryPendingEventValidator`. Cada uno conserva las reglas de su agregado,
la detección de dependencias fallidas y la restauración de sus proyecciones.
`PendingEventDependencyResolver` comparte la consulta de dependencias y la
resolución de la secuencia oficial de un evento base.

El coordinador recorre los pendientes en el orden recibido y comparte los IDs
que ya detectó en conflicto entre todos los validadores. Después marca los
conflictos y restaura sus proyecciones en orden inverso dentro de una sola
transacción. Si falla una restauración, se revierten tanto los cambios de estado
como las restauraciones ya realizadas.

## Actualización de productos y variantes

`producto_actualizado` actualiza el producto y sus variantes activas
atómicamente. El contrato tipado transporta `base_event_id`, `before` y `after`;
ambos estados reutilizan la validación del contrato de producto creado. El
sobre conserva `base_version` y la secuencia oficial conocida. Se mantienen
los identificadores, el evento de creación y la configuración de venta
(modo, unidad y cantidad de referencia del precio). Permite agregar variantes nuevas y retirar variantes existentes con la política de borrado descrita abajo. Las variantes nuevas reciben UUID al guardar y se retiran de la proyección si se revierte el evento.

El formulario conserva el evento base que leyó al abrirse. El comando y el
handler rechazan bases obsoletas. NestJS verifica la base y la forma de venta
contra PostgreSQL, incluso si el cliente altera ambos estados del payload.
Las variantes pueden intercambiar nombres y posiciones dentro de la transacción
sin perder su identidad ni violar temporalmente los índices únicos.

El push espera las bases y recursos locales pendientes. Un cambio oficial
concurrente revierte las ediciones locales dependientes en orden inverso antes
de aplicarse; un eco solo avanza metadatos. Standalone conserva
`delivery_status = not_required` y no persiste `event_refs`.

Cambiar recetas o desactivar seguimiento no modifica saldos ni borra recursos
o movimientos anteriores. Activar seguimiento sin un vínculo existente crea
un recurso mediante el flujo habitual, en el mismo lote local. Los saldos de
un recurso ya vinculado se corrigen mediante movimientos de inventario.


## Eliminación de variantes y del último producto

El editor confirma ELIMINAR y retira inmediatamente la variante del borrador,
tanto en alta como en edición. Se persiste al guardar el artículo; cancelar
el formulario descarta la eliminación. La primera variante restante pasa a ser
la predeterminada. Eliminar la última muestra una advertencia de eliminación
del producto y deja el formulario pendiente de guardar esa eliminación. En un
alta sin persistir, guardar ese estado descarta el borrador sin crear eventos.

La eliminación de variantes viaja en `producto_actualizado` como diferencia
entre `before.variants` y `after.variants`. Para eliminar el producto completo,
el contrato usa `delete_product: true`, `after: null` y conserva `before` como
base validable. Internamente el contrato tipado conserva la base para las
validaciones compartidas. Un cliente anterior rechaza `after: null` en vez de
ignorar silenciosamente la eliminación; todos los dispositivos deben actualizarse.
El comando de eliminación declara referencias `affects` al producto, variantes
y recetas retiradas. No requiere que los recursos históricos sigan activos.

Desde la confirmación de efectivo, la eliminación de catálogo conserva producto y
variantes con `active = false`, incluso sin inventario. Es necesario para aceptar
ventas históricas de dispositivos todavía desconectados. Se preservan recetas,
identidades y referencias de líneas cobradas; no se eliminan recursos, balances ni
movimientos. La limpieza de creaciones en conflicto también protege esas referencias.

Los índices de nombre y posición son únicos solo entre variantes activas. El
recurso directo sigue siendo exclusivo incluso en una variante desactivada.
Los listados y snapshots editables omiten variantes inactivas. Los eventos son
historial auditable y no se borran; el servidor impide reutilizar identificadores
históricos y la repetición de una creación aceptada no resucita un producto.

La versión/base del producto serializa cambios de recetas y vínculos. NestJS
valida `before` contra PostgreSQL, incluyendo recetas, antes de aplicar la
eliminación. Un dispositivo con una base anterior entra en conflicto; no decide
el modo de borrado del servidor. Las nuevas relaciones de negocio que se agreguen
al esquema (por ejemplo ventas) deberán incorporarse a esta política en ambos
proyectores antes de habilitar su uso con borrado físico.

En `server_sync`, `product_update_undo` guarda las filas originales antes de un
borrado optimista para restaurar incluso filas borradas físicamente. La reversión
ocurre en orden inverso y conserva identificadores de creación. El respaldo
local se descarta al restaurar o confirmar su evento. Standalone no genera estos
respaldos de sincronización ni `event_refs`, y conserva `not_required`.

El esquema local mantiene la versión 7 según las reglas de desarrollo. Al abrir
una base anterior sin `sale_payments`, `_resetDatabaseOnStartup` la recrea
una vez; una base actual se conserva. Un respaldo restaurado de esquema anterior
se rechaza sin eliminarlo. PostgreSQL incluye la migración
`1788912000000-AddActiveVariantUniqueness` para los índices parciales.

## Lectura y limpieza del borrador de venta

Búsqueda y caja observan `SaleDraftRepository.watchCurrentDraft`, limitado al
usuario y dispositivo actuales. Una consulta Drift conjunta de `sales` y
`sale_items` mantiene consistentes líneas e importes. El repositorio entrega
modelos de dominio con los snapshots y totales persistidos, sin releer precios
del catálogo. El contador de artículos cuenta variantes distintas; las piezas
y las cantidades medidas se presentan por separado.

`LimpiarVentaBorradorCommand` registra `venta_borrador_limpiada` con las
referencias de la venta y todas sus líneas. El handler borra físicamente primero
las líneas y después la venta dentro de la transacción del evento. El evento
permanece local (`not_required`) en ambos modos; sólo `server_sync` persiste
`event_refs`. El historial se conserva, y su registro de limpieza impide que
reaplicar un evento antiguo de agregado restaure la venta. La siguiente captura
crea un borrador con una identidad nueva.

## Confirmación en efectivo

Implementada mediante `venta_confirmada`; ver [contrato, decisiones, pruebas y límites](cash_sale_confirmation.md).
La revisión del borrador viaja hasta el comando. La configuración de consumo conocida
se compara antes de congelarla; el precio capturado se conserva. Un conflicto de
entrega nunca deshace un cobro ni su consumo.

## Alta de clientes

`Gestión de clientes` abre una lista reactiva de clientes activos, inicialmente
vacía, con `Agregar cliente` abajo a la izquierda. El formulario contiene
`nombre` obligatorio y `telefono` opcional en un campo único. Guardar vuelve al
listado únicamente después de completar la transacción local; un error conserva
los datos para reintentar y el guardado en curso bloquea el doble toque.

El flujo usa `ClienteCommandService`, `ClienteCreadoPayload`,
`ClienteEventHandler`, `ClienteProjectionStore` y `ClienteRepository`. La tabla
Drift `Clientes` hereda `CommonFields` y agrega `nombre` y `telefono`. El evento
`cliente_creado` usa `aggregate_type = cliente`, versión inicial 1, sin base
oficial, y payload `{nombre, telefono}`. Ambos textos se recortan; el teléfono
vacío se normaliza a `null`. No hay unicidad de nombre ni teléfono.

El comando declara una referencia `cliente / <UUID> / affects` en ambos modos.
`DriftLocalEventStore` valida las referencias; en `server_sync` las persiste y
el evento queda pendiente, mientras que en `standalone` aplica el evento con
`delivery_status = not_required` sin persistir `event_refs`. Se mantienen las
restricciones existentes que deshabilitan servicios de sincronización en local.

Push, pull y preflight reutilizan los servicios existentes. El eco de servidor
avanza `lastServerSequence` sin reaplicar campos de negocio. Una identidad
ocupada genera conflicto; una creación oficial sustituye la proyección pendiente
antes de revalidar y retirar el evento perdedor. La limpieza solo elimina la
proyección cuyo `createdEventId` coincide, conservando el ganador oficial.

El esquema local mantiene `schemaVersion = 7`: durante desarrollo, una base sin
`clientes` se recrea en `_resetDatabaseOnStartup`. Una base actual se conserva
en los siguientes arranques; un respaldo antiguo protegido falla explícitamente.

Verificación específica: `test/application/sync/cliente_flow_test.dart` y
`test/presentation/pages/gestion_clientes/clientes_screen_test.dart`.
