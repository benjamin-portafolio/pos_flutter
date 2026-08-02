# Checklist para nueva funcionalidad offline-first

Usa esta lista antes, durante y despues de agregar un flujo similar a `espacio_creado`.

## Antes de codificar

- [ ] Confirmar el agregado que se va a implementar.
- [ ] Confirmar que no se agregara otro agregado no solicitado.
- [ ] Confirmar si el alcance es solo local o incluye sincronizacion remota.
- [ ] Identificar el evento principal, por ejemplo `<agregado>_creado`.
- [ ] Identificar las `LocalEventRef` del agregado y sus claves de negocio.

## Dominio

- [ ] Crear modelo de dominio si la UI necesita leerlo.
- [ ] Crear enums de negocio en `domain`, no en `presentation`.
- [ ] Evitar imports desde `domain` hacia `data`.

## Data local

- [ ] Crear o modificar tabla Drift en `data/local/drift/tables`.
- [ ] Documentar la finalidad de la tabla y el uso de cada campo declarado.
- [ ] Confirmar que los campos heredados esten documentados en su definicion
      comun y aclarar en la tabla cualquier significado particular del agregado.
- [ ] Determinar si la tabla necesita identidad, estado y metadatos comunes de
      trazabilidad o sincronizacion; si los necesita, heredar `CommonFields` y
      no redeclarar sus columnas.
- [ ] Documentar en la tabla y en el agregado cualquier excepcion que impida
      usar `CommonFields`.
- [ ] Crear o modificar DAO en `data/local/drift/daos`.
- [ ] Registrar tabla y DAO en `AppDatabase`.
- [ ] No agregar migracion `onUpgrade` ni subir `schemaVersion` por defecto.
- [ ] Asumir reinicio de base local con `_resetDatabaseOnStartup` hasta que el usuario indique lo contrario.

## Aplicacion

- [ ] Crear `CrearXCommand` o comando equivalente.
- [ ] Crear o extender `XCommandService`.
- [ ] Crear el contrato `XPayload` en `application/sync/payloads`, una clase
      principal por archivo.
- [ ] Declarar `aggregateType` y `eventType` como constantes del contrato.
- [ ] Implementar `XPayload.fromJson` con validacion, normalizacion y
      compatibilidad legada solo cuando corresponda.
- [ ] Implementar `XPayload.toJson` con la representacion canonica.
- [ ] Crear `SyncEvent` con `event_id`, `aggregate_type`, `aggregate_id`, `event_type`, `device_id`, `user_id`, `created_at_local` y `payload`.
- [ ] Construir el payload tipado en el command service y asignar
      `payload.toJson()` al `SyncEvent`.
- [ ] Declarar `LocalEventRef` para el agregado principal y claves de negocio.
- [ ] Llamar `LocalEventStore.appendAndApply(event, refs: ...)`.
- [ ] Mantener `EventsCompanion`, `EventRefsCompanion` y transacciones fuera del command service.
- [ ] Conservar declaracion y validacion de refs en ambos modos.
- [ ] Persistir `event_refs` solo en `server_sync`; standalone debe omitirlas y
      usar `delivery_status = not_required`.

## Sync local

- [ ] Registrar el nuevo `event_type` en `EventProcessor`.
- [ ] Usar la constante `XPayload.eventType` en el registro, sin duplicar el
      literal.
- [ ] Crear o extender el puerto de proyeccion que necesitara el handler.
- [ ] Si la tabla usa `CommonFields`, hacer que el DTO de proyeccion extienda
      `SyncProjection`.
- [ ] Implementar el adaptador Drift de ese puerto en `data/local/drift`.
- [ ] Crear handler en `application/sync/handlers`.
- [ ] Decodificar una vez con `XPayload.fromJson(event.payload)` y usar despues
      solo sus campos tipados.
- [ ] Hacer el handler idempotente.
- [ ] Si un evento afecta varias proyecciones, declarar todas sus referencias y
      aplicar o revertir el conjunto completo dentro de una transaccion.
- [ ] Actualizar la proyeccion local desde el handler.
- [ ] Reutilizar el mismo contrato en cualquier revalidador o consumidor que
      necesite leer campos especificos del evento.
- [ ] Si `base_event_id` puede apuntar a otro evento local pendiente, aplicar
      el dependiente localmente pero diferir su push hasta confirmar la base.
- [ ] Resolver la secuencia oficial efectiva mediante el evento base y
      restaurar cadenas en orden inverso cuando la base entra en conflicto.

## Repository

- [ ] Crear o actualizar repositorio de dominio.
- [ ] Mapear filas Drift a modelos de dominio en `data/repositories`.
- [ ] Evitar que la UI dependa de clases generadas por Drift.

## Presentation

- [ ] Mantener `FormResult` en `presentation` si solo representa el formulario.
- [ ] Convertir `FormResult` a command antes de llamar al service.
- [ ] No insertar directo en Drift desde widgets.
- [ ] Diseñar la pantalla para crecimiento incremental: separar menus,
      formularios, selectores y widgets con responsabilidades independientes.
- [ ] Evitar que la pantalla principal acumule implementaciones de funciones
      futuras o no relacionadas con el agregado actual.

## Verificacion

- [ ] Ejecutar `dart run build_runner build` si hubo cambios Drift.
- [ ] Ejecutar `dart analyze`.
- [ ] Ejecutar `flutter test`.
- [ ] Probar `fromJson`, `toJson`, normalizacion, campos invalidos y formatos
      legados admitidos del payload.
- [ ] Confirmar que no queden accesos manuales a campos especificos de
      `event.payload` fuera del contrato tipado.
- [ ] Revisar que no haya imports de `data/local/drift` desde `domain`.
- [ ] Revisar que no haya imports de `data/local/drift` desde `application`.
- [ ] Revisar que proyecciones de `application/sync` usen `SyncProjection` en
      vez de `CommonFields`.
- [ ] Revisar que no se haya agregado sync remota si no fue solicitada.
- [ ] Confirmar que standalone no inicia push, pull, preflight, health checks ni
      WebSocket.
