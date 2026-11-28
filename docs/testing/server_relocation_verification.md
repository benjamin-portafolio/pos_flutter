# Cambio de dirección y conservación de recuperaciones

Fecha: 2026-11-27.

## Comportamiento

- En Configuración, cambiar la URL de una instalación vinculada comprueba primero
  `/sync/health`: mismo `server_instance_id`, `generation_id`, protocolo 2 y modo
  operativo. Un servidor diferente remite al flujo explícito Recuperar servidor.
- Antes de guardar una dirección nueva, pausa y drena las solicitudes operativas.
  Valida la credencial existente mediante un GET acotado a `/sync/pull` con
  `since=baseline_high_watermark` y `limit=1`. El interceptor de NestJS valida
  dispositivo, token, dataset, generación, vigencia y revocación. La respuesta no
  se aplica al SQLite local ni modifica cursores.
- La dirección autoritativa se guarda atómicamente en
  `server-recovery/installation.json`. La app reabre las dependencias para
  reconstruir endpoint, clientes HTTP, WebSocket y credenciales. Ese archivo sigue
  teniendo prioridad sobre `sync_endpoint.txt`, como antes del cambio.
- La activación tras el primer pull y el cambio de dirección serializan sus
  escrituras para impedir que una activación tardía restaure la URL anterior.
  Conserva la fase `needs_pull` cuando no se ha completado la activación.
- Recuperar servidor ofrece «Cambiar dirección del mismo servidor». Comprueba
  identidad/generación y la sesión remota, incluyendo ID y digest del paquete.
  Si el alta perdió su respuesta, consulta la sesión identificada por la solicitud
  original; solo un 404 permite comprobar elegibilidad antes de la creación.
- Las recuperaciones aprobadas por URL reutilizan el mismo ID y prueba privada
  de autorización. La nueva dirección recibe un alias local de esa prueba después
  de validar la sesión; los siguientes refresh no crean otra solicitud.
- Cambiar la dirección del intento no cambia la URL operativa ni la vinculación.
  Fallos de conexión, identidad, credencial o sesión conservan el diario original.
- «Recuperar en otro servidor» permite, tras confirmación explícita, conservar
  un intento inconcluso en el historial y preparar otro destino. Conserva sesión,
  avance, paquete, captura y autorización. No aborta la sesión remota. El historial
  permite reabrir ese intento cuando no haya otro seleccionado.
- El nuevo destino usa el flujo existente de diagnóstico, aprobación, transferencia,
  publicación y vinculación confirmada. No se transfieren automáticamente las
  credenciales del servidor anterior ni se reemplaza la base al cambiar la URL.
- Standalone rechaza la actualización del intento antes de acceder a archivos o red.
  Cambiar de dirección respeta la política existente HTTPS/HTTP local; usar HTTP
  privado requiere una compilación con `POS_ALLOW_LOCAL_HTTP=true`.

## Verificación automatizada

`test/data/local/recovery/server_relocation_test.dart`:

- Cambio operativo en fases active/needs_pull con SQLite conservado, validación
  autenticada acotada y reapertura usando exclusivamente el nuevo endpoint.
- Identidad/generación diferentes, servidor recuperándose, credencial revocada,
  timeout, redirección y respuesta inválida: archivo anterior sin cambios.
- Recuperación en recepción, completada, antes de crear sesión y con respuesta
  perdida: conserva avance y reutiliza la prueba privada original.
- Sesión de otro paquete o servidor: conserva destino y diario anteriores.
- Standalone sin acceso a red ni archivos.

Pruebas adicionales:

- `test/application/sync/sync_installation_test.dart`: persistencia serializada
  entre activación y cambio de dirección, además de restricciones HTTP existentes.
- `test/application/recovery/recovery_attempt_history_test.dart`: conservación
  explícita y reapertura de un intento inconcluso sin perder evidencia.
- `test/presentation/pages/recovery/recovery_readiness_screen_test.dart`: edición
  explícita, rechazo de otro destino sin alterar avance y confirmación obligatoria
  antes de conservar el intento para preparar otro servidor.

No se cambian tablas, migraciones ni esquema físico de SQLite/PostgreSQL; no
corresponde regenerar el ER. Se validó el contrato contra el interceptor
`src/recovery/server-state.interceptor.ts`, `ServerStateService.business`,
`ConnectionAttemptService` y `RecoverySessionService` del NestJS real.

## Resultados de esta revisión

- `dart analyze`: sin incidencias.
- `git diff --check`: sin errores.
- Las 32 pruebas de los cuatro archivos específicos anteriores pasan en la
  ejecución completa final.
- `flutter test`: 3677 aprobadas, 41 omitidas y 1 fallida. La falla es
  `physical_barcode_assignment_test.dart`, caso «segundo plano conserva asignación
  y exige reanudar antes de agregar», línea 756: espera una línea de venta y recibe
  dos. Se reprodujo el mismo fallo en una copia temporal de HEAD `72f5d5c`, sin los
  cambios de esta tarea. No se modificó ese flujo ajeno a recuperación.
- Las integraciones omitidas requieren fixtures externos; esta revisión no
  ejecuta migraciones ni modifica bases de negocio para habilitarlas.

## Ensayo físico pendiente

Estas pruebas no instalan la app en el celular ni validan una red física. Con una
compilación actualizada, probar cambio de WiFi/IP del mismo servidor conservando
PostgreSQL: actualizar URL en Configuración para operación normal; si hay una
recuperación pendiente, actualizar su URL dentro de Recuperar servidor y usar
«Consultar y reanudar intento». Verificar también reinicio del celular, rechazo
ante una base PostgreSQL recreada y conservación/reapertura desde el historial.
