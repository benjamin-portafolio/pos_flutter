# Proveedores de productos: contrato local y remoto, revisión 1

Las fases 1–7 del plan del 2026-10-07 tienen implementación local y remota.
Catálogo, edición y precios funcionan offline tanto en standalone como en
server_sync. La integración reutiliza comandos, eventos, preflight, push,
pull, restauración y WebSocket existentes. La verificación de fase 7 está en
la sección final y en el informe del repositorio de análisis.

Las secciones de fases 1–6 conservan su evidencia histórica. Sus restricciones
temporales a standalone fueron retiradas en fase 7; la política actual de
modos y compatibilidad se describe aquí y al final del documento.

## Reglas funcionales

- La relación pertenece a la variante. Una variante admite varios proveedores
  y un proveedor varias variantes; la pareja no se repite.
- El proveedor tiene nombre obligatorio recortado, teléfono y notas opcionales
  recortados; vacío opcional se convierte en null. No hay unicidad de nombre
  ni validación de formato telefónico. El teléfono permanece como texto.
- Cada pareja conserva un precio vigente y su fecha informada. Cambiar el
  precio reemplazará la pareja; before/after conservan los valores anteriores.
- quoted_price_minor es un entero JSON en la moneda del POS, de 0 a
  9007199254740991 inclusive (rango seguro Dart/JSON/TypeScript). Cero es un
  precio informado. Ausente, null, texto vacío, negativos, fracciones y valores
  fuera de rango son inválidos; el contrato no convierte strings ni doubles.
  La captura decimal admite coma/punto y como máximo dos decimales;
  convierte a unidad menor sin aritmética de punto flotante. No existe
  conversión de un campo vacío a cero.
- quoted_at_ms es un entero JSON entre 1 y 9007199254740991: instante UTC en
  milisegundos Unix. El productor convierte la fecha informada a UTC antes de
  serializar. No se recalcula al reabrir y no decide conflictos por reloj.
- En venta unitaria, el precio corresponde a una unidad de esa variante. En
  venta medida corresponde a product.sale_configuration.
  price_reference_quantity_atomic y su sale_unit_id. No se agrega otra unidad
  comercial ni conversión de empaque.
- Proveedores coexisten con receta, vínculo directo o ausencia de seguimiento.
  Capturar sus precios no modifica sale_price_minor, standard_cost_minor,
  saldos, movimientos, compras ni gastos.
- Retirar una relación o dejar suppliers: [] no elimina el proveedor. No hay
  bajas de proveedores, proveedor preferido, múltiples monedas ni historial UI.

## Identidad y JSON canónico

El sobre SyncEvent mantiene Map<String, Object?>. Identidades de proveedor,
variante y evento son UUID v4 generados localmente; las nuevas referencias de
proveedor se recortan y serializan en minúsculas. Identidad, device_id, user_id,
created_at_local, base_version y base_server_sequence permanecen en el sobre.
Las clases tipadas nuevas ignoran campos futuros desconocidos y rechazan tipos
inválidos de campos conocidos.

proveedor_creado usa aggregate_type = supplier y aggregate_id = UUID del
proveedor. Payload canónico:

```json
{"name":"Distribuidora Norte","phone":null,"notes":"Entrega semanal"}
```

proveedor_actualizado conserva ese agregado/identidad. Incluye base_event_id
(UUID), before y after completos con el mismo formato del alta. Un cambio de
nombre, teléfono o notas se compara mediante sameState. La fase 2 debe validar
la versión/evento/secuencia conocidos y before contra la proyección antes de
aplicar; before permite reversión. No se inventan versiones en el payload.

Cada variante de producto conocido incorpora:

```json
{"suppliers":[{"supplier_id":"00000000-0000-4000-8000-000000000002","quoted_price_minor":0,"quoted_at_ms":1791331200000}]}
```

La lista se valida sin duplicados y se ordena por supplier_id. El campo es
independiente de inventory_configuration. Todas las variantes del snapshot
conocen suppliers o todas conservan ausencia legada; estados parciales fallan.
Las listas devueltas son inmutables. La extensión se reutiliza en
producto_creado y en before/after de producto_actualizado.

Cada snapshot declara exactamente una dependencia supplier por cada proveedor
presente en sus variantes (unión sin repetidos), ordenada por ref_id:

```json
{"ref_type":"supplier","ref_id":"00000000-0000-4000-8000-000000000002","depends_on_event_id":"00000000-0000-4000-8000-000000000004"}
```

Solo un alta de proveedor local pendiente requiere depends_on_event_id; un
proveedor existente confirmado omite esa clave. Ediciones de su nombre/notas
no son bases del precio del producto. Dependencias faltantes, sobrantes o
duplicadas fallan. dependencyEventIds de la actualización incluye las altas
pendientes de after y su propia base. before conserva su historial, pero no
obliga a entregar un alta por una relación retirada. Borrar producto conserva
before y after:null; no agrega dependencias de after.

Los fixtures bajo test/fixtures/suppliers_v1 son archivos JSON canónicos,
compartibles posteriormente con TS: alta, edición, producto con dos proveedores,
producto medido con receta, conjunto vacío, ausencia legada y retirada explícita.

## Compatibilidad y comprobación de base

ProductoCreadoVariante.proveedores es nullable de manera intencional:

| Entrada | Estado tipado | Significado al aplicar en fases siguientes |
|---|---|---|
| suppliers ausente | null | Evento legado desconoce el conjunto; no autoriza retirada |
| suppliers: [] | lista vacía | Conjunto conocido explícitamente vacío |
| suppliers: [...] | lista completa | Reemplazo explícito con precios/fechas |
| suppliers: null u otro tipo | error | Nunca equivale a lista vacía |

fromJson/toJson preservan la ausencia: no la convierten en []. Las llamadas
existentes a create sin proveedores mantienen el formato anterior para consumidores legados. Los comandos con el puerto de proveedores configurado construyen listas
completas, incluso [], en ambos snapshots, en ambos modos. Un comando que omite la captura conserva las relaciones de la
variante existente; una variante nueva comienza con []. Los eventos históricos y parsers legados conservan su representación
anterior sin suppliers.

ProductoActualizadoPayload rechaza mezclar before desconocido y after conocido,
o viceversa. sameState compara presencia, IDs, precios y fechas; ausencia y
vacío son diferentes. La verificación existente del handler compara la base
actual contra before además de lastEventId/baseVersion: una edición legada
no coincide con un estado que conoce relaciones y debe rechazarse sin escribir.
Los snapshots, la aplicación y los mecanismos existentes de restauración
incluyen las relaciones. Una base legada se edita desde la proyección actual
completa: `_snapshotForEdit` completa con [] los conjuntos desconocidos que
no tienen filas. No construye before desde el evento histórico. `sameEditingBase`
permite solamente esa transición exacta a conjuntos vacíos; `sameState` sigue
distinguiendo ausencia de vacío. Una base que omite suppliers falla contra
un estado conocido, aunque sus conjuntos estén vacíos. El replay histórico
antes de esta transición conserva la ausencia y la aplicación de un campo
omitido no reemplaza relaciones.

## Referencias declaradas por los comandos

| Evento | LocalEventRef requeridas |
|---|---|
| proveedor_creado / proveedor_actualizado | supplier / aggregate_id / affects |
| producto_creado | product / aggregate_id / affects; product_variant / variante_id / affects; variant_suppliers / variante_id / affects para cada conjunto explícito; supplier / supplier_id / uses |
| producto_actualizado | product / aggregate_id / affects; product_variant y variant_suppliers / variante_id / affects para la unión de variantes before/after, incluidas retiradas; supplier / supplier_id / uses para la unión before/after, incluidos proveedores retirados |

variant_suppliers identifica el conjunto por UUID de variante, como recipe;
la pareja no genera un agregado/evento independiente ni requires_unique. No
crear supplier_name/requires_unique. Conservar además refs existentes de
categoría, unidad, inventario, receta y unicidad de nombre de variante. Validar
existencia de proveedores y bases antes de guardar, en la transacción de fase 3.
Para borrado completo, usar la unión procedente de before. La concurrencia
pertenece al producto entero; no fusionar precios por proveedor ni por fecha.

Los command services declaran y validan LocalEventRef en ambos modos.
server_sync persiste event_refs; standalone guarda not_required, aplica la
proyección y no crea event_refs ni ejecuta push, pull, preflight, health checks
ni WebSocket. Importar historial standalone requerirá reconstruir refs de forma
explícita. La UI funciona offline en ambos modos desde fase 7. Guardar no consulta
al servidor. La entrega de nuevos contratos exige la capability descrita abajo.

## Tablas y política de esquema

suppliers es el catálogo de proveedores. Hereda CommonFields: id, active,
version, created_event_id, last_event_id y last_server_sequence. active es
estructural; no introduce bajas. Campos propios: name obligatorio no vacío,
phone nullable y notes nullable. No hay índice único de nombre.

variant_suppliers guarda la relación y el precio vigente. PK compuesta
variant_id/supplier_id evita duplicados. variant_id usa FK CASCADE hacia
product_variants.id; supplier_id usa FK RESTRICT hacia suppliers.id. Sus
quoted_price_minor y quoted_at_ms son NOT NULL, tienen límites compartidos y
CHECK typeof(...)=integer. No tiene índice por proveedor porque todavía no hay
consulta que lo utilice.

Excepción documentada a CommonFields: relación hija reemplazable como
recipe_components, sin identidad/version/evento propios. El agregado producto
conserva concurrencia, before/after y reversión. El borrado físico de variantes
retira hijos en cascada, sin eliminar catálogo; la desactivación histórica de la fase 3 conserva las filas y las excluye de
lecturas activas. Restaurar el producto o variante recupera esas relaciones;
una retirada explícita de proveedores reemplaza solo el conjunto seleccionado.

AppDatabase registra ambas tablas y conserva schemaVersion = 8 y el onUpgrade
preexistente. _resetDatabaseOnStartup exige todas sus columnas mediante
hasCurrentSupplierSchema, dentro de hasCurrentAppDatabaseSchema. Durante desarrollo, el arranque de una base anterior
sin marcador de restauración la recrea según la política vigente. Un respaldo
restaurado incompatible se protege y produce error, sin eliminar su archivo.
Restore valida la versión SQLite actual, el mismo predicado de esquema del
arranque (incluidos proveedores) y foreign_key_check antes de cerrar y
reemplazar la base actual, además de sha256/integrity_check. Un rechazo conserva
la base abierta y sus datos tras reinicio; no crea el marcador de restauración.
Una base actual
se conserva en sucesivos arranques. Todas las pruebas de archivo usan un
path_provider simulado y directorios temporales; no abrir ni reiniciar bases
con datos del usuario para verificar esta entrega.


## Catálogo local: fase 2

`Proveedor` conserva identidad, nombre, teléfono, notas y la base de edición
(evento, versión y secuencia). `ProveedorDao` observa `suppliers` ordenado por
nombre/identidad; `ProveedorRepositoryImpl` devuelve modelos de dominio en un
stream con listas inmutables. No filtra ni introduce una baja por `active`.

El flujo de escritura usa `CrearProveedorCommand`, `EditarProveedorCommand` y
`ProveedorCommandService`, los dos payloads de la fase 1,
`ProveedorCreadoEventHandler`/`ProveedorActualizadoEventHandler` y
`ProveedorProjectionStore`/`DriftProveedorProjectionStore`. Se registran en los
módulos existentes de DI y en el mapa de EventProcessor. El adaptador mantiene
lectura, comprobación de base y appendAndApply en una transacción SQLite. El
handler vuelve a comprobar evento base, versión, secuencia conocida y before
antes de modificar la fila; un fallo revierte también el evento. La edición
conserva id/created_event_id, incrementa versión y reemplaza last_event_id. El
alta repetida reconoce created_event_id incluso después de editar; la edición
repetida reconoce last_event_id. Una identidad de alta ocupada falla.

El servicio reutiliza la normalización de los payloads. Editar sin cambios
normalizados no agrega un evento. Cada escritura declara supplier/affects,
sin unicidad de nombre. DriftLocalEventStore conserva su regla compartida:
standalone guarda applied/not_required sin event_refs; server_sync persiste refs.
Esta fase bloquea el servicio público en server_sync antes de appendAndApply,
para que ningún acceso directo produzca eventos destinados a un servidor sin
estos contratos. La prueba de la persistencia compartida en ese modo invoca el
adaptador explícitamente y no habilita la función ni realiza solicitudes remotas.

Gestión del inventario muestra PROVEEDORES y Añadir proveedor solo con
configuración standalone conocida. El catálogo observa el repositorio y muestra
carga, vacío, error y tarjetas de consulta/edición. El formulario conserva la
base capturada al abrirlo, permite nombre/teléfono/notas y vuelve al catálogo
tras terminar el guardado. Cancelar o volver atrás descarta los controladores
sin llamar al servicio. Guardar bloquea doble toque y salida mientras está en
curso; un fallo mantiene los datos para reintentar. No hay acción de borrar.

Las pestañas se desplazan horizontalmente en teléfonos y se distribuyen en
anchos de tablet. El menú usa una o dos columnas según su ancho y permite
scroll en pantallas bajas; el formulario se desplaza y limita su ancho a 720.
La disponibilidad observa AppConfigController: cambiar a server_sync oculta
la pestaña y la opción incluso si el menú estaba abierto, y bloquea un
formulario ya abierto. El servicio mantiene además su comprobación del modo.

La fase no aplica ni edita variant_suppliers, precios o campos de producto.
AppDatabase solo añade ProveedorDao y su generado; schemaVersion permanece en
8 y onUpgrade no cambia. Las pruebas usan SQLite en memoria o archivos y
path_provider temporales; no abren la base del usuario.

Verificación específica:

- `test/application/commands/proveedores/proveedor_command_service_test.dart`.
- `test/presentation/pages/gestion_inventario/proveedores/proveedor_catalog_test.dart`.
- `test/core/di/proveedor_dependencies_test.dart`.
- `test/support/proveedor_harness.dart`.


## Relaciones con variantes: fase 3

### Captura de dominio y comandos

`PrecioProveedor` admite enteros de 0 a 9007199254740991 sin reutilizar
`PrecioVenta`. `ProveedorVariante` valida identidad UUID v4, precio y fecha
UTC Unix en el rango del contrato, y ofrece una copia canónica e inmutable,
ordenada por identidad y sin proveedores repetidos. No convierte texto ni
fracciones en precios; la captura decimal pertenece al editor de fase 4.

Los constructores `CrearArticuloVarianteCommand.conProveedores` y
`ArticuloFormVarianteResult.conProveedores` copian y congelan la captura.
Los constructores const anteriores conservan proveedores=null y mantienen
compatibilidad con consumidores que no editan ese campo. null en estos datos
internos significa omisión de intención; no se serializa como suppliers:null.
[] es retirada explícita. `VarianteDetalle` también devuelve listas canónicas
inmutables. Identidad y datos de catálogo se leen por el repositorio existente;
los precios no duplican nombre, teléfono o notas del proveedor.

`ProductoCommandService` prepara alta, lote, edición y borrado bajo la
transacción del almacén real. Verifica proveedores de before y after mediante
`ProveedorProjectionStore`, resuelve sus dependencias con el historial y
reutiliza `ProductoProveedorPrecio`/`ProductoProveedorDependencia`. Solo el
alta local pending agrega depends_on_event_id. Una edición del catálogo no
se convierte en base del precio; not_required nunca se promueve a pending.

Si una pareja mantiene su precio, conserva quoted_at_ms anterior aunque el
consumidor reconstruya su lista con otra fecha. Al cambiar el precio se usa la
fecha informada del comando. La retirada y alta de relaciones son explícitas;
no dependen de reloj, nombre o cambios del catálogo. Evento, producto,
variantes, recetas, recursos necesarios y relaciones comparten transacción.
Dos ediciones desde la misma base compiten por el producto completo, incluso
cuando cambian proveedores distintos. No hay fusión por pareja o fecha.

### Proyección, conocimiento y restauración

`ProductoProveedoresProjectionStore` es la capacidad adicional del puerto
existente para reemplazar conjuntos conocidos. El handler de alta inserta
padre, variantes y sus relaciones; el de edición compara evento, versión,
secuencia conocida y before antes de aplicar. Ambos verifican existencia de
proveedores. Los replays del mismo alta/edición conservan idempotencia y no
reinsertan precios ni cambian fechas.

`ProductoDao` lee/reemplaza variant_suppliers. El adaptador obtiene conjuntos
con `supplierSets`, sin exigir reconstruir todo el payload para leer el detalle
legado. Esto conserva las lecturas preexistentes de productos que tienen
metadatos o identidades antiguas; solo los datos de proveedor aplican sus
invariantes nuevas. Los helpers tipados `knowsSuppliers` consultan el campo
sin reinterpretar otros campos históricos. Si hay variantes en esos
metadatos, mantienen el rechazo de null y snapshots parciales.

El conocimiento es del agregado y permanece una vez acreditado por snapshots
registrados del producto (incluido before al revertir) o filas actuales de
relaciones. supplierSets devuelve un mapa conocido con todas las variantes
activas, incluso vacías, o ausencia legada para todo el agregado. No usa
`event_refs`, relojes ni una columna/migración nueva. Los eventos revertidos
conservan conocimiento sin conservar precios retirados; los eventos de una
transacción fallida desaparecen y no acreditan conocimiento. Así, deshacer
la primera edición moderna de un producto legado conserva before completo
con [] también después de cerrar y reabrir SQLite. Los cambios de categoría
no borran ese conocimiento. El reconstruidor de seguimiento usa la misma
comparación limitada para admitir esta transición vacía sin inventar una
historia de inventario.

Reemplazar un conjunto vacío elimina sus parejas y conserva el catálogo.
Reordenar variantes o editar nombre, barcode, receta, seguimiento, venta o
costo conserva las listas omitidas. Retirar una variante o artículo lo
mantiene inactivo con sus relaciones históricas, como las recetas. Un borrado
físico por los mecanismos existentes aplica CASCADE; nunca borra suppliers.

`product_update_undo.snapshot_json` añade suppliers con las filas de todas las
variantes, incluidas las inactivas. Restaurar ese respaldo recupera listas,
precios, fechas y metadatos originales y elimina relaciones de variantes
añadidas que se retiran físicamente. Un respaldo anterior sin esa clave
conserva las relaciones de variantes retenidas; la ausencia no autoriza
limpiarlas. La restauración fallback usa before completo, respeta listas
omitidas y aplica [] explícitamente. Ambos caminos usan los mecanismos y
transacciones existentes. Respaldo de archivo y reapertura conservan las
tablas ya implementadas en fase 1.

### Formularios, importación y modos

Detalle → `ArticuloPreviewForm` → editor de variante → `copyWith` → comando
conserva proveedores y fechas al abrir/guardar otros campos. La comparación
del borrador incluye las relaciones. Reconstruir la variante en modo sencillo
conserva identidad y proveedores. No se agregan campos visibles, selector,
resumen de precios ni navegación; corresponden a fase 4.

La importación CSV actual da de alta nuevos artículos y pasa por el mismo
command service: en standalone construye [] sin alterar relaciones de
artículos existentes. No hay formato CSV de proveedores. La opción de edición
masiva permanece sin acción implementada; no se inventó otro flujo de edición.

La captura nueva, incluido [], se rechaza en server_sync. DI inyecta el puerto
de catálogo y la comprobación del modo en el handler. Además, un evento con
suppliers conocidos requiere not_required y ninguna server_sequence, por lo
que un acceso directo al handler no habilita la integración remota. Altas,
ediciones y borrados server_sync de artículos legados conservan payloads y
refs anteriores. La persistencia compartida de event_refs no cambia.
Standalone declara refs, guarda applied/not_required, tiene cero event_refs y
no resuelve ni ejecuta servicios remotos. Las fases 6–7 siguen pendientes.

### Verificación de fase 3

- `test/application/commands/articulos/product_supplier_relations_test.dart`:
  49 pruebas de dominio, comandos, SQLite, fixtures, concurrencia, rollback,
  idempotencia, compatibilidad, restauración y reapertura.
- `test/presentation/pages/gestion_inventario/articulos/product_supplier_forms_test.dart`:
  4 pruebas de conservación y capturas inmutables.
- `test/core/di/proveedor_dependencies_test.dart`: 1 prueba nueva de producto
  con DI real, SQLite/path_provider temporal y HTTP/WebSocket bloqueados.
- `test/support/product_supplier_harness.dart` reutiliza el harness existente
  de seguimiento, puertos y procesadores reales con SQLite aislado.
- `dart analyze`: sin problemas. `flutter test --reporter expanded`: 1493
  aprobadas y 1 omisión preexistente (Nest/PostgreSQL aislado no configurado).
- Drift regenerado; AppDatabase, tablas, schemaVersion=8, onUpgrade y
  DriftLocalEventStore permanecen idénticos a la base inicial. El generado
  solo añade accesores del DAO. No se usó la base del usuario ni se inició
  la aplicación en un dispositivo físico. El siguiente paso es fase 4.


## Editor local de precios: fase 4

### Pantallas y borradores

`InventoryManagementScreen` entrega `ProveedorRepository` y
`AppConfigController` al formulario del artículo. `ArticleFormScreen` pasa el
catálogo, la configuración actual y la configuración de venta al editor de
variante. `VariantEditorScreen` mantiene su propia lista canónica/inmutable y
abre `VariantSuppliersEditorScreen` desde ADMINISTRAR PROVEEDORES, independientemente
de receta o seguimiento directo. La consulta muestra `VariantSuppliersSummary`
con nombres del catálogo, precios, fechas y base del precio, sin acceso al selector.

El selector observa el catálogo local, distingue carga/error/vacío y ofrece
reintento de lectura sin perder el borrador. Cada proveedor se selecciona con
un checkbox; los campos aparecen solamente para selecciones explícitas. Un
mapa por identidad evita duplicados. Desmarcar retira la pareja del resultado;
volver a marcar conserva lo capturado durante esa apertura. Una recarga no
retira selecciones aunque falte una identidad: la muestra y exige recuperar el
catálogo o retirarla explícitamente. Una lista vacía se puede guardar. No hay
alta en el selector: se indica crear proveedores desde PROVEEDORES.

`ProveedorPreciosFormResult` copia/ordena/congela el conjunto y solo vuelve al
borrador de variante. GUARDAR en variante lo devuelve al borrador de artículo;
únicamente GUARDAR artículo utiliza el command service existente. Cancelar en
cualquiera de los tres niveles descarta los cambios correspondientes sin
escrituras de relaciones/eventos. La comparación del artículo incluye las
parejas y sus fechas, así que un cambio de proveedores habilita Guardar; abrir
y guardar sin cambios conserva la comparación de identidad. Un error atómico
al guardar el artículo mantiene el borrador y admite reintento.

### Dinero, fecha y base del precio

`ProveedorPrecioInput` valida dígitos con una fracción opcional de uno o dos
decimales; admite coma/punto, espacios exteriores y cero explícito. Convierte
con BigInt, comprueba el límite antes de convertir a int y formatea con división
entera/resto. 90071992547409.91 equivale exactamente al máximo de
`PrecioProveedor`. Vacío, negativos, signos, separadores de miles, exponentes,
fracciones incompletas/más precisas y exceso de rango producen error por campo.
No se filtra una captura inválida hacia un precio anterior ni se interpreta
vacío como cero/retirada. No se reutiliza `CurrencyInputFormatter`, cuya captura
firmada y rechazo de edición no coinciden con estas reglas; venta/costo
conservan sus componentes preexistentes.

`ProveedorPrecioForm` mantiene la relación original. Con un precio equivalente,
reutiliza su instante exacto, incluidos milisegundos, y deshabilita cambiar fecha,
con una explicación visible. Para una selección nueva se propone la fecha local
actual al seleccionarla; es editable. Al cambiar un precio existente, la fecha
informada sigue visible y se puede elegir otra mediante calendario. Se usa esa
fecha al construir la pareja y se convierte con `toUtc().millisecondsSinceEpoch`.
El calendario captura el día local a medianoche. Cancelarlo conserva la fecha.
El reloj solo propone una fecha de captura; nunca determina conflictos.

El rango del contrato supera el de DateTime. Una relación con un instante no
representable se consulta como milisegundos UTC y se conserva sin convertir;
cambiar su precio exige seleccionar una fecha válida. La UI no reduce el rango
del precio ni altera fechas persistidas al abrirse.

El selector identifica artículo/presentación y muestra una unidad vendible en
venta unitaria, o `priceReferenceQuantityAtomic` con la unidad real del producto
medido mediante `InventoryQuantityCodec`. El formulario comparte esa misma
configuración con el guardado y conserva la original en edición. El core actual
requiere que la referencia medida coincida con el factor de la unidad; no se
amplió esa regla ni se agregaron unidades comerciales/conversiones.

### Modo, separación y archivos

Acceso, resumen y navegación requieren catálogo y configuración standalone
conocidos. Las pantallas observan cambios de modo; el selector abierto oculta
campos/Guardar en server_sync y comprueba el modo antes de seleccionar, elegir
fecha y devolver el resultado. El editor comprueba el modo al abrir y recibir
el selector, y bloquea entregar una variante con proveedores modificados si
el modo cambió. Los comandos/handlers de fases anteriores conservan su defensa;
no se habilita integración remota ni se cambian los payloads legados.

Pantalla, tarjeta de campos, resumen y modelos tienen archivos separados:

- Nuevos en `lib/presentation/pages/gestion_inventario/articulos/models/`:
  `proveedor_precio_input.dart`, `proveedor_precio_form.dart` y
  `proveedor_precios_form_result.dart`.
- Nuevos en `lib/presentation/pages/gestion_inventario/articulos/widgets/`:
  `variant_suppliers_editor_screen.dart`, `proveedor_precio_card.dart` y
  `variant_suppliers_summary.dart`.
- Ampliados: `widgets/variant_editor_screen.dart`, `article_form_screen.dart`,
  `models/articulo_form_result.dart` (comentario) e
  `../inventory_management_screen.dart` (inyección hacia formularios).
- Pruebas nuevas en `test/presentation/pages/gestion_inventario/articulos/`:
  `proveedor_precio_form_test.dart`, `variant_suppliers_editor_test.dart` y
  `product_supplier_ui_flow_test.dart`.

Los únicos ajustes al flujo anterior son pasar catálogo/modo/base de precio,
conservar el borrador y reconocer una variante con proveedores como no vacía.
No cambia application/domain/data/DI, esquema, schemaVersion=8, onUpgrade ni
el generado. No se regenera Drift. Se preservan las funciones y cambios locales
preexistentes de fases 1–3 y Cotizaciones.

### Verificación de fase 4

- 66 pruebas nuevas: `proveedor_precio_form_test.dart` (33),
  `variant_suppliers_editor_test.dart` (26), `product_supplier_ui_flow_test.dart`
  (7). Incluyen UI real con comandos/repositorios/SQLite en archivo temporal,
  cancelación en tres niveles sin escrituras, alta/edición/reapertura, retirada
  del último, fallo de proyección/rollback/reintento y conservación de venta/costo.
- `dart analyze`: sin problemas. `flutter test --reporter expanded`: 1559
  aprobadas y 1 omisión remota preexistente que requiere POS_PHASE3_SYNC_URL.
- Interfaz standalone: eventos applied/not_required, cero event_refs y cero
  HttpClient con HTTP/WebSocket bloqueados. La suite conserva la prueba DI
  de fases anteriores que no activa el runtime remoto.
- Layout automatizado: 320×640 y 740×360, texto 1.3; 1280×800, texto 1.5.
  Selector/editor/consulta sin overflow; scroll y acción Guardar accesibles
  con insets de teclado simulados 260/170/300. Se renderizaron y revisaron
  seis PNG con fuentes Roboto/MaterialIcons del SDK (apertura/precio enfocado).
  El render opcional de tests usa POS_SUPPLIER_PREVIEW_DIR y
  POS_SUPPLIER_PREVIEW_FONTS; la suite ordinaria no necesita esos parámetros.
- No se realizaron pruebas físicas ni se abrió la base del usuario. Al cerrar
  fase 4 quedaba pendiente la aceptación de fase 5, completada a continuación.
  Evidencia en el vault: Proveedores de productos/Evidencia/2026-10-08-fase4.

## Verificación local y cierre: fase 5

Aceptación local satisfecha el 2026-10-08. Se reutilizaron las pruebas de
fases 1–4 y se añadieron ocho casos en
`test/data/local/drift/supplier_local_acceptance_test.dart` para huecos reales:

- Alta/edición por comandos reales, dos proveedores y tres variantes con
  precios/fechas independientes, proveedor compartido y lista vacía; otro
  conjunto con catálogo y relaciones explícitamente vacíos.
- Dos reaperturas de AppDatabase real antes del snapshot; respaldo SQLite con
  el servicio existente (VACUUM INTO y SHA256); restore en otro directorio
  temporal; dos reinicios y lecturas por repositorios e interfaz real. Se
  comparan todas las tablas Drift, identidad, datos, relaciones y eventos.
  El origen modificado después del snapshot permanece intacto.
- Rechazo de SHA incorrecto, archivo no SQLite, columna requerida renombrada
  y versiones 7/9 sin cerrar/reemplazar la base vigente. Se mantienen los
  casos anteriores para esquema de proveedores ausente/incompleto y FK huérfana.
- Variante con stock directo y otra con receta; Caja abierta, cotización
  guardada y venta confirmada por servicios existentes. Capturar precios
  conserva las filas no vacías de ventas, pagos, Caja, Cotizaciones, recetas,
  saldos y movimientos, además de venta/costo y configuración de consumo.

Las pruebas detectaron que restore aceptaba un esquema incompatible fuera de
las tablas de proveedor o una versión distinta. La corrección extrae sin
cambiar su lógica el predicado existente de arranque a
`lib/data/local/drift/current_database_schema.dart` y lo reutiliza desde
`DriftDatabaseRestoreService`, junto con la versión numérica. No cambia tablas,
DAOs, generado, schemaVersion=8 ni onUpgrade; no se regeneró Drift. La regresión
de respaldo legado de Cotizaciones distingue rechazo de restore de protección
de un archivo legado ya presente durante el arranque.

Verificación final: dart analyze sin problemas; flutter test --reporter json
con 1567 aprobadas, cero fallidas y una omisión remota preexistente;
git diff --check sin errores. La corrida enfocada de aceptación y respaldos
tuvo 48 aprobadas. Standalone conserva applied/not_required, cero event_refs,
cero pendientes y cero HttpClient con HTTP/WebSocket bloqueados. Se mantienen
declaración/validación de refs, defensas server_sync y flujo legado de artículos;
no se promueve historial standalone a pending.

Evidencia en el vault: Proveedores de productos/Matriz de aceptacion local.md,
Verificacion local - fase 5.md y Evidencia/2026-10-08-fase5, con resultados por
prueba, comandos, hashes/deltas y datos sintéticos de respaldo/restauración.
Se conservan los cambios preexistentes. Ningún archivo de presentación cambió;
se reutilizan las seis capturas revisadas de fase 4 y se repiten sus tests de
layout/scroll/Guardar en teléfono/tablet con insets de teclado simulados.

No hubo pruebas físicas ni acceso a datos del usuario. No se verificó upload
de respaldo en cuenta remota, NestJS/PostgreSQL, transporte ni dos terminales.
La omisión requiere POS_PHASE3_SYNC_URL y no acredita validación remota.
La función continúa disponible únicamente en standalone; fases 6–7 pendientes
de una solicitud explícita de integración remota.


## Servidor implementado: fase 6

El contrato de servidor se documenta en
`/Users/benjamin/Library/CloudStorage/GoogleDrive-benjamin94833@gmail.com/My Drive/Projects/POS/pos-nest/docs/product_suppliers.md`.
Usa copias literales de los siete fixtures Dart existentes; los manifiestos de
fase 6 comparan SHA256. Los tests Dart de payloads vuelven a pasar sin modificar
fuentes o fixtures de Flutter.

NestJS conserva quoted_price_minor/quoted_at_ms como bigint y comprueba el rango
seguro antes de persistir; quoted_at_ms nunca se convierte a Date. Las
relaciones pertenecen al producto completo, sin versión independiente ni
arbitraje por fecha. Creación/edición de proveedor validan identidad, base,
versión, secuencia y before. La transacción comprende evento, proyección y refs;
producto incluye variantes, recetas, relaciones y memoria de inventario.

El conocimiento de suppliers se reconstruye desde las filas actuales y los
metadatos del último evento aceptado, incluso para conjuntos []. sameState
mantiene ausencia != vacío; sameEditingBase permite únicamente la promoción
legada vacía definida aquí. Un cliente antiguo que reconstruya snapshots sin
el campo se rechaza cuando la base ya conoce proveedores; omitir nunca retira.
La dependencia explícita debe corresponder al alta aceptada original del
proveedor, aunque después se haya editado; before no obliga a entregar altas
para relaciones retiradas. Refs de conjuntos/proveedores retirados se conservan.

Las verificaciones PostgreSQL se ejecutaron en una instancia temporal y esquemas
sintéticos, sin acceder a bases del usuario. Pull y los endpoints mantienen su
formato y entregan todos los eventos aceptados; no hay filtrado por versión ni
negociación de capacidades. Los parsers antiguos pueden ignorar o rechazar los
campos/tipos nuevos: el servidor protege escrituras, y la fase 7 debe coordinar
la compatibilidad de lectura y habilitación. JavaScript no distingue 1.0 de 1
tras JSON.parse; valida el valor entero seguro y rechaza strings/fracciones/
excesos. No se añadió un parser léxico a los endpoints.

No se modifica standalone/server_sync, no se promueven eventos not_required y
no se importa su historial. La evidencia y los resultados finales están en
`Proveedores de productos/Verificacion servidor - fase 6.md` del repositorio de
análisis. El cierre de servidor no equivale al cierre remoto ni habilita la UI
de proveedores en server_sync.


## Integración de fase 7: contrato vigente

### Disponibilidad y bases

ProveedorCommandService admite crear/editar offline en server_sync. El editor,
catálogo, pestaña, menú y consulta de precios permanecen disponibles al cambiar
entre modos. Los handlers leen tanto eventos pendientes como oficiales. Una
edición con base causal pendiente declara base_server_sequence=null; espera
la confirmación de esa base antes del push. El resolvedor existente consulta
su secuencia oficial por base_event_id para revalidar. El handler compara una
secuencia de base cuando el sobre la proporciona, y siempre comprueba evento,
versión y before. Los ecos de proveedores avanzan solo lastServerSequence:
conservan campos, versión, createdEventId y ediciones optimistas posteriores.

Un proveedor pendiente declara depends_on_event_id=createdEventId en los
productos que lo usan. Editar nombre/notas no cambia esa causalidad. Push difiere
el producto hasta confirmar el alta, y difiere ediciones de producto/proveedor
hasta confirmar su base. Solo las dependencias de after y la base obligan la
entrega; las relaciones retiradas de before conservan refs e historia, sin
exigir entrega de sus altas históricas. Una dependencia rechazada/conflictiva
bloquea sus descendientes y los reclasifica en la transacción existente.

### Restauración y proyección oficial

ProveedorPendingEventValidator se registra en PendingEventRevalidator; producto
valida también proveedores y sus altas causales. SyncConflictProjectionCleaner
reutiliza ProveedorConflictProjectionRestorer y la eliminación del alta local.
Solo restaura una edición si lastEventId sigue siendo su evento; un cambio
posterior vigente queda protegido. RemoteEventPreparer deshace cadenas del
proveedor que compiten con un evento oficial, antes de proyectarlo.

Las cadenas se retiran de último a primero, incluidas las dependencias de
producto de un alta rechazada/colisionada, antes de eliminar el proveedor con
FK RESTRICT. Rechazos de proveedor/producto se restauran conjuntamente con sus
dependientes. No cambia la política de rechazos de otros agregados.
Producto conserva el respaldo existente product_update_undo: producto,
variantes activas/inactivas, recetas, precios/fechas y memoria de inventario.
Solo las secuencias de eventos delivered acreditan una base oficial al
restaurar; una secuencia de conflict/rejected nunca reemplaza la oficial.
No hay recuperación paralela, fusión por proveedor ni resolución por reloj.

### Compatibilidad y transporte

SyncService.health anuncia capabilities: ["product_suppliers_v1"]. Antes de
un push que incluya proveedor_creado/actualizado o un snapshot de producto
con suppliers explícito, SyncPushService comprueba el health del endpoint con
el transporte existente. Capability ausente, health inválido o desconexión
impiden el envío del lote; los cambios permanecen pendientes y visibles. No
hay consulta remota en cada guardado ni caché de capacidades entre endpoints.
Los servidores anteriores no reciben los nuevos payloads. Tampoco se presupone
que preserven campos desconocidos. El rechazo de escrituras legadas sobre un
conjunto conocido conserva el estado oficial, incluyendo [].

**Actualización coordinada obligatoria:** actualizar el servidor, retirar del
servicio los clientes antiguos mientras se actualizan todas las terminales y
activar el uso de proveedores solo con todos los lectores compatibles. Pull
distribuye todos los tipos aceptados y no filtra por versión. La capability
certifica el servidor; no certifica las versiones de todas las terminales.
No se agregó registro de versiones ni un filtro de pull.

EventProcessor rechaza tipos desconocidos antes de aplicar la página, incluidos
ecos; pull y preflight rechazan elementos que no sean eventos, sin filtrarlos.
La transacción existente comprende eventos, proyecciones y checkpoint. Un fallo
conserva cursor y datos anteriores. Una terminal nueva reconstruye el catálogo
y productos por pull desde cero; WebSocket conserva sync:events_available y
el aviso de reconexión que dispara el pull existente. No hay bootstrap nuevo.

### Standalone y esquema

Standalone mantiene applied/not_required, cero event_refs y cero pendientes.
LocalEventRef se declara/valida en ambos modos. No se inicia preflight, push,
pull, health o WebSocket en standalone. Cambiar el modo no transforma el
historial: comandos remotos rechazan editar bases standalone y utilizar altas
standalone sin una importación explícita. Ningún evento not_required se promueve.
No se cambian tablas, schemaVersion=8 ni onUpgrade; no se regenera Drift.

La evidencia final distingue terminales lógicas (SQLite independientes con
device_id distinto) de dispositivos físicos. No hubo pruebas físicas,
despliegue, migración de bases del usuario ni acceso a sus datos.


Verificación final de fase 7: dart analyze sin problemas; flutter test con 1578
aprobadas, cero fallos y cero omisiones. Incluye nueve escenarios nuevos contra
NestJS/PostgreSQL/HTTP/WebSocket reales, cuatro protecciones complementarias y
la regresión remota preexistente activada. NestJS: build aprobado y 507 pruebas
PostgreSQL sin omisiones. git diff --check aprobado en los tres repositorios.
Informe/matrices/resultados en Proveedores de productos/Verificacion remota -
fase 7.md y Evidencia/2026-10-08-fase7 del repositorio de análisis.
