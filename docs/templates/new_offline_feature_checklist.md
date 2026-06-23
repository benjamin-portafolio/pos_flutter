# Checklist para nueva funcionalidad offline-first

Usa esta lista antes, durante y despues de agregar un flujo similar a `espacio_creado`.

## Antes de codificar

- [ ] Confirmar el agregado que se va a implementar.
- [ ] Confirmar que no se agregara otro agregado no solicitado.
- [ ] Confirmar si el alcance es solo local o incluye sincronizacion remota.
- [ ] Identificar el evento principal, por ejemplo `<agregado>_creado`.
- [ ] Identificar claves de negocio que requieran `event_refs`.

## Dominio

- [ ] Crear modelo de dominio si la UI necesita leerlo.
- [ ] Crear enums de negocio en `domain`, no en `presentation`.
- [ ] Evitar imports desde `domain` hacia `data`.

## Data local

- [ ] Crear o modificar tabla Drift en `data/local/drift/tables`.
- [ ] Crear o modificar DAO en `data/local/drift/daos`.
- [ ] Registrar tabla y DAO en `AppDatabase`.
- [ ] Agregar migracion si cambia el esquema.

## Aplicacion

- [ ] Crear `CrearXCommand` o comando equivalente.
- [ ] Crear o extender `XCommandService`.
- [ ] Crear `SyncEvent` con `event_id`, `aggregate_type`, `aggregate_id`, `event_type`, `device_id`, `user_id`, `created_at_local` y `payload`.
- [ ] Insertar evento en `events` con `sync_status = pending`.
- [ ] Insertar `event_refs`.
- [ ] Aplicar el evento con `EventProcessor.apply(event)`.
- [ ] Mantener todo lo anterior en una transaccion local.

## Sync local

- [ ] Registrar el nuevo `event_type` en `EventProcessor`.
- [ ] Crear handler en `application/sync/handlers`.
- [ ] Hacer el handler idempotente.
- [ ] Actualizar la proyeccion local desde el handler.

## Repository

- [ ] Crear o actualizar repositorio de dominio.
- [ ] Mapear filas Drift a modelos de dominio en `data/repositories`.
- [ ] Evitar que la UI dependa de clases generadas por Drift.

## Presentation

- [ ] Mantener `FormResult` en `presentation` si solo representa el formulario.
- [ ] Convertir `FormResult` a command antes de llamar al service.
- [ ] No insertar directo en Drift desde widgets.

## Verificacion

- [ ] Ejecutar `dart run build_runner build` si hubo cambios Drift.
- [ ] Ejecutar `dart analyze`.
- [ ] Ejecutar `flutter test`.
- [ ] Revisar que no haya imports de `data/local/drift` desde `domain`.
- [ ] Revisar que no se haya agregado sync remota si no fue solicitada.
