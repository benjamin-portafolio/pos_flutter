# Guia para Codex en este proyecto

Este proyecto usa un flujo offline-first por eventos. Antes de implementar una funcionalidad similar a `crear espacio`, lee:

- `docs/architecture/offline_feature_flow.md`
- `docs/templates/new_offline_feature_checklist.md`

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
-> guardar events y event_refs
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
- Enums o conceptos de negocio viven en `domain`.
- Las tablas Drift y DAOs viven en `data/local/drift`.
- Los handlers de eventos deben ser idempotentes.
- `domain` no debe depender de `data`.
- La UI no debe insertar directo en Drift.

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
