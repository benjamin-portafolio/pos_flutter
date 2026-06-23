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
  -> crear SyncEvent
  -> guardar events con sync_status = pending
  -> guardar event_refs
  -> EventProcessor.apply(event)
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

`domain`

- Contiene modelos, enums y reglas de negocio.
- No importa `data/local/drift` ni clases generadas por Drift.
- No conoce detalles de SQLite.

`application/commands`

- Convierte una intencion de negocio en uno o mas eventos.
- Guarda el evento y sus referencias dentro de una transaccion.
- Aplica el evento localmente despues de guardarlo.
- Usa `LocalCommandContext` para `deviceId` y `userId`.

`application/sync`

- Contiene `SyncEvent`.
- Contiene `EventProcessor`.
- Contiene handlers que aplican eventos a proyecciones locales.
- Los handlers deben ser idempotentes.

`data/local/drift`

- Define tablas, DAOs, migraciones y base local.
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
lib/application/sync/event_processor.dart
lib/application/sync/handlers/espacio_event_handler.dart
lib/data/local/drift/tables/espacios.dart
lib/data/local/drift/tables/events.dart
lib/data/local/drift/tables/event_refs.dart
lib/data/local/drift/daos/espacio_dao.dart
lib/data/repositories/espacio_repository_impl.dart
lib/domain/repositories/espacio_repository.dart
```

## Event refs

Cada evento debe registrar al menos una referencia al agregado principal:

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
