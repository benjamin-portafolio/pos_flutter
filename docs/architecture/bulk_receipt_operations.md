# Edición masiva: recepción y diario local

El core de recepción coordina el comando comercial de `ProductoCommandService`
y `InventoryCommandService.registrarEntradaConfirmada`. La interfaz pública de
Gestión del inventario usa ese mismo core,
sin añadir eventos, contratos de servidor o transporte. Conserva los
payloads `producto_actualizado` y `movimiento_inventario_registrado` vigentes.

## Uso desde aplicación

1. Preparar/revisar el borrador de sesión 1. Una revisión con errores no se
   confirma. Las filas sin cambios se omiten antes de reservar.
2. Crear una identidad de captura una sola vez (por ejemplo UUID v4) y llamar
   `EdicionMasivaCommandService.confirmar(batchId: ..., cambios: ...)`. Agrupa
   variantes por producto y reserva todo el conjunto en una transacción.
   Confirmar no escribe catálogo, movimientos, eventos, refs ni respaldos.
3. Llamar `continuar(batchId)` explícitamente, o `ejecutar(operacion)` para un
   producto. El lote se ejecuta secuencialmente y devuelve resultado/error por
   producto después de su commit/rollback. Los fallos dejan la reserva
   confirmada; los otros productos pueden continuar.
4. Al reabrir, consultar `pendientes()`. No hay ejecución desde constructores,
   apertura de base ni servicios de arranque. Mostrar los pendientes y exigir
   una acción explícita para continuar; la ejecución vuelve a validar las bases.
5. Una propuesta obsoleta conserva su intención. Para sustituirla, cerrar sus
   pendientes mediante `cerrarPendientes(batchId)` y preparar/confirmar otra
   captura con otro batchId y solo los productos pendientes revisados. Los
   aplicados conservan su evidencia y nunca se incluyen como nueva recepción
   implícita. La revisión ofrece «Revisar sobre estado nuevo»: conserva textos,
   muestra las nuevas bases/saldos, cierra pendientes antiguos y exige otra
   confirmación. Un cambio de vínculo/unidad requiere retirar y recapturar
   explícitamente su entrada; no interpreta la cantidad con otra unidad.

`DriftDiarioEdicionMasiva(db, config, context)` compone internamente lecturas,
comandos, historial y handlers sobre **la misma instancia AppDatabase**. El
puerto `DiarioEdicionMasiva.transaccion` proporciona esa unidad de trabajo de
aplicación sin importar Drift. No acepta un almacén serial como sustituto de
la transacción exterior. Las transacciones interiores participan en el mismo
commit SQLite; un fallo revierte eventos, refs, respaldos, catálogo, saldos,
movimientos y resultado de ese producto. La reserva previa permanece.

## Identidad, intención y resultado

`OperacionEdicionMasiva.operationId` es UUID v5 del par captura/producto con
namespace/formato fijo. No depende del orden del listado ni se regenera al
reintentar. El JSON canónico versionado ordena variantes por ID y conserva
valores enteros normalizados, conservar/establecer, proveedor/fecha UTC,
base de producto, vínculo al recurso, unidad completa y revisión del saldo.
Su lectura reconstruye la misma solicitud para recuperación.

La ejecución primero busca la operación y compara esa intención. Si está
aplicada devuelve el resultado original antes de exigir bases antiguas, incluso
si el catálogo avanzó, el saldo cambió o un evento entró en conflicto. Si el
mismo ID lleva otra intención, se rechaza sin escribir. Una operación cerrada
no se puede ejecutar. Una pendiente reservada en otro modo queda bloqueada;
consultar resultados aplicados bajo otro modo solo lee evidencia.

Para pendientes se releen actividad, pertenencia, producto/base y, por entrada,
seguimiento directo sin receta, vínculo, recurso/base, unidad y saldo/base
confirmados. Los ecos pueden acreditar secuencias de las mismas bases mediante
los mecanismos existentes. Un evento/versión distinto requiere otra revisión;
no se sustituye por la base viva ni se infiere ejecución por el saldo resultante.

Se emite como máximo un evento comercial por producto y un `stock_receipt`
positivo por recurso con entrada. La variante estricta de inventario valida
la revisión dentro de una transacción real, exige historial local, comprueba
representabilidad/rango y devuelve IDs de recurso, evento y movimiento. Los
otros consumidores de `registrarMovimiento` conservan su semántica actual.
`total_cost_minor` permanece null. No existe dependencia remota ficticia entre
el evento comercial y el movimiento.

`ResultadoOperacionMasiva` guarda el ID del evento comercial si se emitió y los
IDs devueltos por cada entrada. No busca «el último evento». `eventos(resultado)`
consulta después la entrega/conflicto actual de esos eventos en el historial:
commit local y aceptación remota son estados distintos. Reintentar un evento
remoto corresponde al sync existente y no vuelve a invocar recepción.

## Esquema y conservación

`bulk_edit_operations` es un diario local, **no una proyección sincronizable**.
Es una excepción explícita a CommonFields: no representa un agregado con
active/version/created_event_id/last_server_sequence; registra ejecución de
una intención confirmada y no participa en pull/push ni genera event_refs.
Cada campo se documenta además en la tabla Drift:

| Campo | Finalidad |
|---|---|
| operation_id | Identidad determinista de captura/producto y PK |
| batch_id, product_id | Agrupación y destino estables; índice único conjunto |
| mode | Modo de confirmación, standalone o server_sync |
| intent_json | Solicitud canónica con intención, bases, unidad y saldo confirmados |
| local_state | confirmada, aplicada o cerrada; nunca aceptación de servidor |
| result_json | IDs/resultados originales; no nulo solamente si aplicada |
| confirmed_at | Reserva UTC antes de iniciar negocio |
| finished_at | Commit/cierre UTC; nulo mientras confirmada |

El producto no tiene FK: borrar un producto no debe borrar evidencia contra
reintentos. No hay purga automática. Tabla y DAO están registrados en
AppDatabase. `hasCurrentAppDatabaseSchema` exige sus columnas e índice junto
con el esquema anterior. `schemaVersion` sigue en 8 y no se añade onUpgrade.
El arranque recrea una base de desarrollo anterior; una vigente se conserva.
Un respaldo restaurado protegido de esquema anterior se rechaza sin borrarlo.

El mecanismo existente `VACUUM INTO` y restore con hash, integrity_check,
foreign_key_check y comprobación de esquema incluye el diario completo junto
con sus eventos/proyecciones. No se añade otro sistema de respaldo. La garantía
al reabrir se limita a la evidencia conservada en esa misma base/snapshot:
un reset de desarrollo elimina también el diario; restaurar un snapshot viejo
no recupera operaciones posteriores a él. No reconstruir ni reejecutar esas
operaciones suponiendo que nunca ocurrieron.

En ambos modos los comandos declaran/validan LocalEventRef mediante el almacén
vigente. Solo server_sync las persiste y mantiene entrega pendiente. Standalone
conserva not_required y cero event_refs; este core no crea servicios de
push/pull/preflight/health/WebSocket. Continuar en otro modo o usar historial
standalone en server_sync no convierte ni importa sus eventos.

## Verificación

- `test/application/commands/edicion_masiva/edicion_masiva_command_service_test.dart`:
  SQLite real, conservación, validación, modos, idempotencia y triggers de fallo
  después del catálogo, después del primer movimiento y antes del resultado.
- `test/application/commands/edicion_masiva/recepcion_reapertura_test.dart`:
  arranque real con path_provider aislado, reapertura sin reset, esquema y
  snapshot/restore; un subproceso flutter_tester termina con SIGKILL antes o
  después del commit y se reabre la misma SQLite. El helper de ese subproceso
  está en `test/support/recepcion_masiva_crash_worker.dart` y no forma parte de
  los tests descubiertos automáticamente.

Las pruebas usan datos sintéticos. No acreditan aceptación remota, rendimiento
formal, UI ni comportamiento en dispositivo físico; corresponden a las sesiones
posteriores del plan.

## Recorrido público

«Edición masiva» del menú de inventario abre por tarea o recepción compacta.
Ambas composiciones usan `ControladorEdicionMasiva`, el mismo borrador por ID,
revisión y `confirmar`/`ejecutar`; no existe otro guardado. Compacta muestra
costo/venta juntos y existencias/entrada/previsto debajo, con referencia comercial
y unidad real de ingreso. El proveedor predeterminado solo afecta nuevas
capturas de costo; detalle conserva proveedor/fecha propios por fila.

Al abrir se consultan las reservas pendientes para ofrecer recuperación, sin
continuarlas. El historial permite consultar aplicados, continuar pendientes,
revisarlos o cerrarlos explícitamente. Recopila nombres del catálogo por ID;
si un destino ya no existe, conserva el ID del diario. Los aplicados recuperan
su resultado original y nunca se copian como otra entrada al borrador. La UI
protege las capturas nuevas al continuar otra operación del mismo producto y
bloquea una nueva confirmación si hay una reserva anterior sin resolver.

El avance se publica cuando `ejecutar` termina su transacción, incluso en fallo.
Doble confirmación queda bloqueada. Cancelar o volver durante el guardado pide
detener pendientes, conserva la ruta y espera al producto activo. El resultado
separa aplicados, omitidos, fallidos y no iniciados; los fallidos siguen reservados.
Una ruta destruida externamente ignora la respuesta tardía y no inicia el siguiente.

Los resultados consultan `eventos` por los IDs guardados, con actualización
explícita de entrega por evento. Catálogo y cada entrada pueden estar pendientes,
aceptados o en conflicto/rechazo de forma distinta. El resultado del diario
acredita el commit local histórico; no acredita aceptación remota indivisible
ni sustituye la restauración/revalidación de sincronización ya existente.

Verificación del recorrido y DI: `recepcion_recorrido_test.dart`,
`recepcion_compacta_screen_test.dart`, `inventory_management_screen_test.dart`
y `edicion_masiva_dependencies_test.dart`. Los tests de entrega parcial asignan
estados sintéticos a eventos de SQLite para verificar presentación; no acreditan
integración HTTP ni restauración real. La integración HTTP real se verifica en sesión 6; dispositivo físico sigue
pendiente.

## Verificación de sesión 6

`test/integration/recepcion_masiva_server_test.dart` reutiliza el arnés de
seguimiento/proveedores con NestJS/PostgreSQL aislados y dos archivos SQLite.
Requiere `POS_BULK_SYNC_URL`, `POS_BULK_PG_SCHEMA` y `DATABASE_*` del entorno
sintético. Verifica respuesta perdida después de aceptar, reapertura/reenvío de
los mismos IDs, proveedor y bases pendientes, capability ausente, aceptación
parcial en ambos sentidos, conflictos y resolución de precio sin otra entrada.
Las aserciones consultan además saldos/movimientos directamente en PostgreSQL.
Los fallos de respuesta, capability y sobre inválido se inyectan en el cliente
HTTP de pruebas; las decisiones y transacciones siguen siendo del servidor real.

La entrada estricta emite `base_server_sequence = null` si su base es local
pendiente: la secuencia heredada pertenece al antecesor, no a esa base. La
entrega continúa dependiendo del `base_event_id` existente. Un rechazo de
movimiento usa la restauración local vigente, con la misma protección por evento
y versión. Antes de aplicar un recurso oficial remoto se restaura su cadena
optimista en orden inverso; los ecos aplicados conservan su camino anterior.
No se cambian contratos, política de servidor ni atomicidad remota.

`recepcion_verificacion_test.dart` añade accesibilidad automatizada y comprueba
que un catálogo SQLite de 10000 variantes consulta páginas de 100 sin lecturas
de detalle al abrir/buscar y construye solo campos visibles. Las pruebas previas
conservan teclado simulado, Siguiente, revisión y recorrido público.
`tool/benchmarks/recepcion_masiva_verification.dart` mide con SQLite en archivos,
un calentamiento excluido y cinco corridas por combinación de catálogo,
captura y modo. No se ejecuta como umbral de CI.

La consulta de recuperación sigue leyendo/decodificando el diario completo y
resolviendo nombres por conjuntos. No hay purga ni paginación de ese historial;
su costo de memoria/lectura crece con las operaciones retenidas. El benchmark
separa lectura del comando y controlador, y mide bytes asignados. No acredita
el render de un historial arbitrariamente grande, latencias garantizadas ni
rendimiento de una tablet. La prueba móvil física sigue pendiente.
