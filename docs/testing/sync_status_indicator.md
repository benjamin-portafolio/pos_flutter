# Indicador de sincronización del dispositivo

El encabezado principal y el menú comparten `SyncStatusController`. Abrirlos no
inicia tráfico. En standalone muestran «Modo local» sin resolver los servicios de
sincronización. El detalle ofrece «Comprobar ahora» mediante el monitor existente.

## Evidencia para el estado verde

- Recorrido exitoso de recepción del orquestador, incluyendo páginas aplicadas,
  o comprobación del cursor contra una secuencia recientemente informada por el
  servidor. Un envío termina comprobando recepción aun si preflight vació la cola.
- Ninguna operación de sincronización activa o fallida en ese recorrido.
- Consulta local disponible, cero pendientes de entrega, cero conflictos,
  rechazos o eventos con aplicación fallida. Los conflictos ya reportados al
  servidor también cuentan como incidencias.
- Servidor disponible según el monitor y comprobación de menos de un minuto.

La fecha representa la última comprobación exitosa de recepción, incluso cuando
no hubo eventos para descargar. Se mantiene durante la sesión para consulta;
reiniciar exige obtener evidencia nueva. Cada diez segundos se actualiza la edad
visible; al vencer la vigencia se muestra «Sincronización por comprobar». No se
introducen sondeos ni rutas remotas nuevos.

Una desconexión o un nuevo pendiente fuera de un recorrido invalida la evidencia;
volver a conectar o vaciar la cola por sí solos no la restablecen. Un fallo de
recepción automática se conserva para el detalle y evita una excepción sin manejar.
Los problemas se consultan con su motivo e identificador; esta tarea no incorpora
un flujo para resolverlos ni los marca atendidos automáticamente.

El indicador confirma este dispositivo con el servidor, sin garantizar que los
otros equipos hayan enviado sus cambios. No calcula un porcentaje ni un contador
de recepción desconocido. El diálogo del encabezado respeta la compuerta de
navegación de Caja y restaura el lector al cerrarse.

## Verificación automatizada

- `test/application/sync/sync_status_controller_test.dart`: cola vacía y conexión
  insuficientes, caducidad, pendientes nuevos, incidencias, lectura local fallida,
  desconexión y errores durante operaciones concurrentes.
- `test/application/sync/sync_orchestrator_test.dart`: integración de la evidencia
  con recepción, envío sin cambios y avisos automáticos.
- `test/data/local/drift/drift_sync_status_store_test.dart`: consulta reactiva real
  en SQLite en memoria; conflictos reportados, rechazos y aplicación fallida.
- `test/presentation/pages/pantalla_principal/server_connection_indicator_test.dart`:
  modo local, consulta de problemas, comprobación manual, ancho de 320 px y
  navegación denegada/permitida.

Sin cambios de esquema; no requiere regenerar Drift ni actualizar el ER.

## Resultado de esta implementación

- `dart analyze`: sin incidencias.
- Suite enfocada en estado, orquestador, disponibilidad, consulta SQLite,
  indicador, menú, shell y navegación de Artículos: 52 pruebas aprobadas.
- `flutter test` completo: 3658 aprobadas, 41 omitidas y 1 fallo.
- El fallo es `segundo plano conserva asignación y exige reanudar antes de
  agregar`, en `physical_barcode_assignment_test.dart:756`: espera una línea y
  obtiene dos. Se reprodujo con el comando aislado siguiente. Ese recorrido monta
  `CajaScreen` directamente, sin el indicador, su controlador, monitor ni
  orquestador; no se amplió esta tarea al flujo de asignación de códigos.

```sh
flutter test test/presentation/pages/caja/physical_barcode_assignment_test.dart \
  --plain-name 'segundo plano conserva asignación y exige reanudar antes de agregar'
```

Las pruebas del indicador cubren además la respuesta tardía posterior a una
invalidación por desconexión y el repintado del detalle al caducar la comprobación.
No se ensayó en esta tarea contra un servidor físico.
