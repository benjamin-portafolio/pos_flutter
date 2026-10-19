# Existencia mínima por variante: persistencia, sincronización e interfaz (sesiones 1–4)

Implementado el 2026-10-19. Contratos, esquema y persistencia local están
integrados; el receptor y transporte están verificados en sesión 3. La sesión 4
habilita la captura compartida y el informe observable. Verificación física y
cierre integral siguen para sesión 5.

`product_variants.minimum_stock_atomic` es un entero nullable de
0 a 9007199254740991. Son átomos de la dimensión del recurso vinculado;
null desactiva el aviso y cero es válido. No tiene unidad independiente,
no cambia saldos y no se obliga a borrarlo al retirar el vínculo.
SQLite exige `typeof = integer` para valores no nulos, además del rango.

## Presencia y compatibilidad

- `ProductoCreadoVariante.minimumStockAtomic` contiene el valor.
  `knowsMinimumStock` distingue ausencia legada de null explícito.
  En `create`, un número acredita conocimiento; para null explícito se
  proporciona `knowsMinimumStock: true`. El null por defecto de llamadas
  anteriores sigue representando desconocimiento, no intención de borrar.
- `fromJson` y `toJson` preservan la omisión histórica. Todas las variantes
  deben conocer el campo o todas deben omitirlo. Before y after también deben
  compartir conocimiento. Un borrado conserva before y emite after=null.
- `withKnownMinimumStock()` promueve una lectura legada a null conocido sin
  reescribir historia. Conserva valores existentes, proveedores, recetas y
  dependencias. `withKnownSuppliers()` conserva a su vez el mínimo y su presencia.
- `sameState` compara el valor del mínimo; ausencia y null no difieren en
  negocio. Así la normalización de presencia no exige por sí sola un evento.
  `sameEditingBase` valida aparte que una base conocida jamás admita un before
  legado, incluso para borrar. La promoción legada solo admite mínimos null;
  no relaja ningún otro campo ni la compatibilidad de proveedores.
- Los checks de evento, versión y secuencia siguen siendo responsabilidad de
  los consumidores actuales. El handler local rechaza el escritor legado con
  «Actualiza la app» incluso sobre un mínimo conocido null; el receptor aplica
  la misma guarda desde sesión 3.

El equivalente TypeScript usa `minimumStockAtomic?: number | null`:
undefined es ausencia; null explícito es conocimiento. Ambos runtimes admiten
valores numéricos enteros seguros (incluido 1.0) y rechazan strings, booleanos,
fracciones no enteras, negativos, desbordamiento y no finitos. JavaScript no
conserva la grafía JSON 1.0 frente a 1; no se añade un parser de tokens.
El codec existente convierte 1.5 kg a 1500 átomos sin double y rechaza fracciones
de pieza o precisión excesiva. El comando usa ese mismo codec para el mínimo.

## Esquema y evidencia

Drift mantiene schemaVersion=8, sin onUpgrade nuevo. El detector compartido por
arranque y restore exige la columna; arranque recrea una base incompatible de
desarrollo y protege una restaurada. Las pruebas solo abren archivos temporales.
`app_database.g.dart` se regenera con `dart run build_runner build`.

Los fixtures `test/fixtures/minimum_stock_v1/contracts.json` son idénticos a los
de NestJS. Las pruebas focalizadas están en
`test/application/sync/minimum_stock_contract_test.dart` y
`test/data/local/drift/minimum_stock_schema_test.dart`. Acreditan contratos,
SQL real, detección, reapertura y backup/restore directo del campo.
No acreditan persistencia por eventos, ambos modos, undo ni convergencia.

## Persistencia local y conservación (sesión 2)

`CrearArticuloVarianteCommand.minimumStock` reutiliza `CambioExplicito<String?>`:

- `const CambioExplicito.conservar()` es el valor por defecto de ambos
  constructores. Ninguna llamada anterior expresa una retirada implícita.
- `CambioExplicito.establecer('1,5')` convierte la cantidad con
  `InventoryQuantityCodec`, en la unidad de inventario validada por el comando.
- `const CambioExplicito.establecer(null)` retira explícitamente el mínimo.
  Establecer o retirar requiere seguimiento directo activo; conservar permite
  desvincularlo, cambiar a receta y mantener el umbral dormido.

La validación de unidad/dimensión y la recuperación de recursos reutilizan el
resolver existente. Una venta por gramos con inventario en kg interpreta el
mínimo en kg. Un mínimo nuevo o retirado no modifica la clave de consumo,
saldos ni movimientos. Al recuperar el vínculo, la regla usa el saldo vigente.
Las creaciones actuales declaran el campo en todas sus variantes, incluido null.
Una edición de historia legada lo conserva ausente salvo intención explícita;
esta última promueve before/after completos. Un guardado idéntico, incluida
promoción de presencia a null sin cambio de negocio, no emite eventos ni undo.

Valor y conocimiento viajan por proyección, snapshot, detalle/listado de dominio
y repositorio observable. La presencia se reconstruye desde el evento señalado
por `products.last_event_id`, consultando los helpers tipados del contrato.
No se deduce de SQL null, no acumula intentos rechazados y no usa event_refs.
Un mínimo físico no null también protege contra metadata histórica legada,
incluso en variantes retiradas. La consulta observable une el evento base y
consulta valores físicos por producto, sin peticiones por fila ni escrituras.
La política de proveedores permanece independiente.

Barcode, CSV y edición comercial superponen únicamente sus campos sobre el
snapshot, preservando mínimo y presencia. La edición completa conserva por
omisión, incluidas recetas/proveedores y variantes retiradas; la recepción usa
el mismo comando comercial dentro de su transacción existente. Los encabezados
CSV permanece sin captura del mínimo; la UI se conecta en sesión 4.

`product_update_undo` ya serializa filas completas con la columna generada en
sesión 1 y el evento base que acredita conocimiento. Se corrigió su restauración
con `toCompanion(false)`: un null respaldado debe escribirse explícitamente
sobre la fila optimista, en lugar de omitirse en un upsert. La guarda existente
por last_event_id impide que una restauración tardía pise una base posterior.
Standalone utiliza la reversión de snapshot sin crear respaldos de sync.

`domain/inventario/minimum_stock_policy.dart` contiene la regla compartida:
saldo físico <= mínimo conocido no null y producto, variante y recurso activos
con seguimiento directo. Null desactiva; cero incluye saldos cero y negativos.
No importa Drift ni genera eventos. Sesión 4 la conecta al contador, filtro y
filas del informe existente.

Ambos modos declaran/validan refs; solo server_sync las persiste. Standalone
conserva not_required y no importa historial local a pendientes. No se añadieron
servicios remotos, tablas, migraciones ni generación Drift en sesión 2.

La evidencia local nueva está en
`test/application/commands/articulos/minimum_stock_local_test.dart`, sobre
`ProductSupplierHarness`/`VariantTrackingHarness` existentes. Las pruebas CSV,
edición comercial y recepción/reapertura ahora incluyen mínimos reales y
mantienen sus verificaciones de atomicidad, undo, respaldo y saldos.
El registro completo de comandos, resultados y límites está en el vault,
Alertas de existencias mínimas/Evidencia/2026-10-19-sesion2/README.md.

## Sincronización verificada (sesión 3)

El receptor NestJS conserva mínimo y conocimiento desde la base aceptada vigente.
Permite historia legada y promoción explícita, protege valores físicos con metadata
legada y rechaza edición/borrado antiguo sobre base conocida con «Actualiza la app».
Canónico y pull preservan ausencia/null/valor; la reentrega no degrada conocimiento.
No se cambiaron los contratos, comandos, esquemas ni persistencia Flutter de
sesiones 1–2 para conseguir esta compatibilidad.

`test/integration/minimum_stock_server_test.dart` añade siete recorridos al arnés
existente: dos clientes actuales y replay a cliente vacío, mínimos null/cero/máximo
y medido, preflight y cambios concurrentes entre variantes, cadenas pendientes,
reapertura SQLite en disco, rechazo con undo, borrado optimista y restauración
tardía tras un sucesor aceptado. Los rechazos de tipo/parcial/base se envían por
HTTP al receptor real; no son aceptaciones simuladas. Se comprueba que modificar
solo mínimo conserva recursos, balances, movimientos, ventas/líneas/pagos en SQL
real y no cambia la clave de consumo ni impide confirmar una venta abierta.

Habilitar POS_MINIMUM_SYNC_URL y POS_MINIMUM_PG_SCHEMA contra una instancia del
arnés Nest `test/support/variant-tracking-server.ts`, con DATABASE_HOST loopback,
DATABASE_NAME pos_nest_test_* y psql en PATH. La regresión HTTP completa usa una
instancia/schema por suite y las variables POS_PHASE3_SYNC_URL,
POS_SUPPLIER_SYNC_URL/POS_SUPPLIER_PG_SCHEMA y POS_BULK_SYNC_URL/POS_BULK_PG_SCHEMA.
No compartir targets entre suites concurrentes que comparan tablas completas.
Los comandos, URLs y resultados reales constan en el vault, evidencia de sesión 3.

Standalone mantiene not_required y cero event_refs persistidos/actividad remota;
la regresión local conserva esas guardas. No se añaden endpoints, cron ni
WebSocket de alertas. La sesión 4 conecta la captura pública al mismo flujo de comandos.
En un despliegue futuro, receptor/esquema compatibles deben estar disponibles
antes de habilitar escritores nuevos; esta sesión no despliega ni migra datos
operativos.


## Editor e informe (sesión 4)

`ArticuloFormVarianteResult.minimumStockAtomic` es el valor precargado de consulta,
incluso si el seguimiento está desactivado. `minimumStock` es la intención
`CambioExplicito<String?>`, conservar por defecto en ambos constructores.
Preview/copyWith/conversión a comando preservan esa separación: abrir un campo
vacío de una base legada y guardar otro dato no promueve su conocimiento.
El editor compara con la captura inicial y conserva intenciones de borradores al
reabrirlos; cambiar a vacío retira explícitamente y cero configura un umbral real.
Desactivar seguimiento o activar receta envía conservar, manteniendo el mínimo
persistido dormido. Cancelar el editor o el artículo no guarda la captura.

El campo muestra la unidad del inventario aun vacío, limita teclado y precisión
con `InventoryQuantityInputFormatter` y valida con `InventoryQuantityCodec`.
Artículos usa la unidad de la variante existente y conserva la referencia de
venta, también para inventario en kg con venta en gramos. Cambiar solo mínimo
habilita Guardar artículo; el guardado conserva las demás variantes/campos y la
base capturada. Una base obsoleta muestra el error y exige reabrir; no se recarga
ni sustituye automáticamente. Los movimientos guardados desde el editor siguen
siendo independientes y sobreviven a cancelar el mínimo.

`RemainingStockItem.isLow` aplica `MinimumStockPolicy` al catálogo y balance ya
observados. Fila, filtro Todas/Existencias bajas y contadores usan ese resultado;
la tarjeta conserva el total de seguimiento y añade Existencias bajas. El informe
muestra mínimo/unidad o Sin mínimo, distintivo Existencia baja y vacío específico
cuando el filtro no coincide. Ventas confirmadas, ajustes, reposiciones y mínimos
actualizados cambian la vista desde el stream existente, sin temporizadores, red,
eventos de alerta ni consultas o sumas por fila.

`test/presentation/pages/informes/minimum_stock_ui_test.dart` contiene 25 pruebas:
intenciones y 12 recorridos por modo con widgets, comandos/eventos/proyecciones y
SQLite real aislado. Incluye venta confirmada, recepción masiva y última fila que
desaparece, igualdad/cero/null/medidos, alta sencilla/avanzada, otras variantes,
barcode sobre legado, cancelación, base fija, mínimo dormido y movimiento
independiente. Las pruebas de tamaño 320/1024 con texto x2 no acreditan hardware.
La regresión local no sustituye las pruebas HTTP de sesión 3 ni el cierre de 5.
No cambiaron contratos, esquemas, core, backend, CSV ni captura masiva en sesión 4.


## Verificación final (sesión 5)

`test/presentation/pages/informes/minimum_stock_restore_test.dart` integra informe,
edición, SQLite en disco y servicios reales de snapshot/restore en ambos modos.
Conserva valores medidos, null conocido, ausencia legada, undo y todas las tablas;
comprueba aviso/contador/filtro y segunda reapertura de una base restaurada protegida.
La regresión final aprueba 2567 pruebas, incluidas las 23 HTTP con cuatro schemas
propios, sin fallos/omisiones. Analyze limpio; build macOS del main de producción.
Código Nest sin cambios: build/587 PostgreSQL de sesión 3 vigentes por SHA256.
Manual sobre la app completa macOS con directorios temporales: mínimo cinco,
venta 6→5, aviso, reposición 5→6, retirada, edición/vacío y reapertura en piezas/kg.
A01–A41 verificados; A42 parcial por falta de teléfono/tablet físico (teclado
decimal, legibilidad, scroll y navegación reales pendientes). No hay cierre total.
Registro: vault, Alertas de existencias mínimas/Evidencia/2026-10-19-sesion5/README.md.
No cambió código funcional/esquema ni hubo despliegue o migración operativa.
