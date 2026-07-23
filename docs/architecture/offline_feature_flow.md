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
lib/application/commands/crear_espacio_command.dart
lib/application/commands/espacio_command_service.dart
lib/application/sync/models/sync_event.dart
lib/application/sync/payloads/espacio_creado_payload.dart
lib/application/sync/payloads/categoria_creada_payload.dart
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
