# Escaneo en inventario: verificación y cierre

Fecha: 2026-10-15. HEAD: `d4e66bb`, rama `main`, con fases 1 y 2 aún sin
confirmar en Git. Fase 3 completada para verificación automatizada. I01–I19
aprobados en ese ámbito; I20 físico pendiente por decisión expresa del usuario.

## Acceso implementado

Gestión del inventario → Artículos muestra «Escanear código de barras» sobre
`+`. Una coincidencia abre edición ubicada en la variante; varias requieren
elección explícita. Un código desconocido ofrece seleccionar una variante
existente y confirmar asignación o reemplazo, mostrando ambos códigos cuando
corresponde. El éxito aparece después de guardar localmente y vuelve a inventario.
No incorpora productos ni líneas de venta. Cancelar antes de confirmar no escribe.

## Evidencia y ejecución

Se revisaron los AGENTS de Flutter y del vault, ambas guías offline, el plan y
la continuidad antes de trabajar. Se preservaron los 13 archivos previos de
fases 1/2 y los cambios ajenos del vault. Solo se ampliaron dos archivos de
pruebas; los nueve archivos de producción previos permanecen idénticos al
inicio de fase 3. No hubo defectos funcionales encontrados ni correcciones de
producción, esquema, dependencias o transporte remoto.

La evidencia general aprobada de fase 2 se reutiliza conforme al plan: el
código de producción no cambió y el único consumidor del fixture modificado
es la prueba de navegación ejecutada de nuevo. No se presenta esa suite como
una ejecución nueva de fase 3 ni se suma artificialmente un total nuevo.

| Comando / evidencia | Resultado y alcance |
|---|---|
| `dart analyze` (fase 3, resultado final) | Salida 0, `No issues found!`; [log conservado](evidence/inventory_barcode_phase3/analyze.log) |
| `flutter test test/presentation/pages/gestion_inventario/articulos/inventory_barcode_flow_test.dart --reporter expanded` | Salida 0, **33 aprobadas**, 0 omisiones/fallos, 23 s; incluye 31 existentes y 2 nuevas. [Log conservado](evidence/inventory_barcode_phase3/navigation.log) |
| `flutter test test/application/commands/articulos/asignar_codigo_barras_variante_test.dart --reporter expanded` | Reutilizada de fase 2: 60 aprobadas, 0 fallos; código y prueba intactos. Log `/tmp/pos_flutter_barcode_phase2_contract.log` |
| `flutter test --reporter expanded` | Reutilizada de fase 2: **2064 aprobadas, 10 omitidas, 0 fallos**, salida 0, 1 min 58 s. Log `/tmp/pos_flutter_barcode_phase2_full_test.log` |
| `dart format --output=none --set-exit-if-changed` (dos archivos Dart propios) | 0 cambios pendientes |
| `git diff --check`, `rg`, comparación SHA-256 | Sin whitespace incorrecto ni piezas nuevas sin consumidor; [manifest de preservación y logs](evidence/inventory_barcode_phase3/manifest.json) |
| `flutter devices --machine`; `system_profiler SPCameraDataType` | Simuladores iPhone 17/iPad Pro 13-inch (M5), Chrome y macOS 27.0.1 con MacBook Air Camera. Sin teléfono/tablet físico conectado. No se ejecutó cámara nativa |
| `dart run build_runner build` | No aplica: sin cambios de tablas, DAOs ni esquema |

Las 10 omisiones previas son integraciones que requieren `POS_SUPPLIER_SYNC_URL`
o `POS_PHASE3_SYNC_URL` con servidor aislado, fuera del alcance. No hubo fallos
previos ajenos que ocultar ni regresiones detectadas. El manifest registra los
hashes iniciales/finales de esta sesión y los logs previos disponibles; no
pretende ser una captura histórica de los hashes al ejecutar fase 2.

## Recorrido nuevo con archivo SQLite temporal

Las dos pruebas `CSV sin barcode: asigna, reabre y reemplaza conservando
coincidencias compartidas en standalone/serverSync` cubren el hueco entre
importación, interfaz y reapertura, sin repetir los contratos ya cubiertos:

1. Validan un CSV real de dos productos y tres variantes sin barcode; lo
   importan mediante `ArticuloImportBatchService` y comandos reales. Café tiene
   Chico/Grande con costos distintos y Grande tiene seguimiento con saldo 7;
   Agua no tiene nombre de variante ni seguimiento. Comprueban todos los códigos
   inicialmente `null` y conservan un borrador de venta previo.
2. Desde el lector de inventario, la cámara falsa entrega ` ０００４２ `.
   La consulta de `00042` no coincide; aviso → selector → Grande → confirmación
   de asignación → guardado real produce un solo `producto_actualizado`.
3. Comparan el payload completo salvo el barcode elegido y las dependencias
   causales; comparan todas las tablas ajenas a proyección/metadatos de producto.
   Ventas, líneas, recursos, saldos, memoria y movimientos quedan intactos.
4. Desmontan las pantallas, cierran SQLite y abren **el mismo archivo**; todas
   las filas coinciden con el estado guardado. La consulta normalizada encuentra
   Grande por `00042`, no por `42`; escanearlo abre la edición real de Grande
   y cancelar conserva todas las tablas.
5. Preparan otra variante con el código compartido, verifican dos coincidencias
   y desde inventario escanean `00043` desconocido para reemplazar solo Grande.
   Confirman código actual/nuevo, un evento y conservación del resto.
6. Tras otra reapertura, `00043` resuelve Grande, `00042` solo Chico y `43`
   ninguna. El evento queda aplicado con `not_required`/`pending` según modo,
   refs declaradas en ambos y persistidas únicamente en `server_sync`.

Todo vive en `Directory.systemTemp.createTemp('pos_inventory_barcode_')` y
`AppDatabase.forTesting(NativeDatabase(file))`; los directorios se eliminan al
terminar. No se abre `AppDatabase()` ni la base/catalogo de uso del usuario.

## Matriz I01–I20

**UI**: [prueba de navegación e integración](../../test/presentation/pages/gestion_inventario/articulos/inventory_barcode_flow_test.dart), 33 aprobadas en fase 3.
**CMD**: [prueba del comando](../../test/application/commands/articulos/asignar_codigo_barras_variante_test.dart), 60 aprobadas reutilizadas.
Los nombres o fragmentos de nombres citados se pueden buscar literalmente en esos archivos.

| ID | Resultado | Evidencia concreta |
|---|---|---|
| I01 | Aprobado automatizado | UI `lector sobre + solo en Artículos; + conserva su menú`: posición, ausencia en otras tres pestañas y apertura del menú |
| I02 | Aprobado automatizado | UI `una coincidencia abre edición ubicando la segunda variante, sin escribir`; también nueva consulta tras reapertura del CSV, variante correcta y estado completo intacto al cancelar |
| I03 | Aprobado automatizado | UI `varias coincidencias requieren elección explícita, cancelar=false/true`: producto/variante/precio, sin detalle antes de elegir ni escrituras; CMD conserva códigos compartidos |
| I04 | Aprobado automatizado | UI `confirma asignación…` y CSV: código desconocido visible, oferta de asignación antes del selector, sin alta automática |
| I05 | Aprobado automatizado | UI `búsqueda por artículo y variante, con/sin código y existencias; sin detalle por fila`: seis filas, filtros combinados y una sola lectura del destino |
| I06 | Aprobado automatizado | UI `asigna a variante sin nombre, sin barcode ni seguimiento de existencias`; búsqueda también incluye Light con seguimiento |
| I07 | Aprobado automatizado | UI confirmación de asignación y CSV en ambos modos: null → `00042`, un evento aplicado, persistencia y repositorio |
| I08 | Aprobado automatizado | UI confirmación de reemplazo y CSV: actual `00042`, nuevo `00043`, solo Grande cambia; CMD `reemplaza solo el destino, permite compartidos y persiste al reabrir` |
| I09 | Aprobado automatizado | UI `cancelar lector/aviso/selector/confirmación conserva todas las tablas` y cancelación de coincidencias/edición; sin eventos ni cambios en inventario/venta |
| I10 | Aprobado automatizado | UI CSV: NFKC/trim, `00042`/`00043` persisten como texto; `42`/`43` no coinciden. CMD prueba ceros y límites 1/32 dígitos |
| I11 | Aprobado automatizado | UI incompatible y 33 dígitos muestran error y permiten reescanear; frames vacíos se ignoran sin consulta/escritura. CMD rechaza vacío/incompatible/33 dígitos sin cambios |
| I12 | Aprobado automatizado | UI base obsoleta muestra `009` y pide otra confirmación; variante retirada bloquea guardar. CMD producto/variante ausentes/inactivos, ajena y base obsoleta/vacía sin cambios |
| I13 | Aprobado automatizado | UI `destino ya igual informa sin invocar comando`; CMD `mismo código normalizado no escribe ni cambia metadatos` |
| I14 | Aprobado automatizado | UI doble toque/guardado, lecturas repetidas/doble apertura y consulta/detalle tardíos tras cerrar; una operación, cámara detenida y sin navegación/escritura tardía |
| I15 | Aprobado automatizado | CMD `conserva snapshot completo, inventario y venta (medido=false/true)` en ambos modos: proveedores/fechas, receta, variante histórica, precios/costos/identidades/vínculos. UI CSV y guardados conservan venta/inventario |
| I16 | Aprobado automatizado | CMD rollback íntegro ante persistencia, aplicación y base al aplicar; comparación de todas las tablas y reintento; replay dos veces idéntico. UI fallo tras aplicación conserva código/destino y permite reintentar |
| I17 | Aprobado automatizado | UI CSV en ambos modos reabre dos veces el archivo, compara todas las filas y consulta código nuevo/anterior/compartido; CMD además conserva historial before/after del reemplazo |
| I18 | Aprobado automatizado local | CMD refs declaradas y almacén rechaza refs vacías en ambos modos; standalone sin refs/undo/pendientes y `not_required`; runtime no resuelve monitor remoto. server_sync con refs `local_pending` y `pending`. UI CSV revalida entrega/refs después del guardado y filas al reabrir |
| I19 | Aprobado automatizado | Suite general aprobada reutilizada, incluidos editor, búsqueda de ventas y lectores de Caja; UI CSV compara venta/líneas y no incorpora ninguna al asignar/reemplazar |
| I20 | **Pendiente físico** | UI con `FakeMobileScannerPlatform` prueba permiso denegado/no disponible, cancelación, pausa/reanudación y permiso pendiente al cerrar. Ninguna de esas pruebas acredita cámara/lectura nativa. Usuario eligió «Dejar la prueba física pendiente» |

Las regresiones reutilizadas incluyen
`variant_editor_barcode_test.dart`, `article_search_screen_test.dart`,
`article_search_item_test.dart`, `sale_barcode_scanner_screen_test.dart`,
`physical_barcode_reader_test.dart` y `test/presentation/pages/caja/barcode/`.
El lector de Artículos de ventas y los dos accesos de Caja conservan sus
contratos. No se desarrolló transferencia de códigos ni unicidad.

## Pendiente físico concreto

1. En un teléfono/tablet físico o en el Mac cuando se disponga de etiquetas de
   prueba, usar datos aislados y registrar plataforma/modelo/SO, formato y valor
   textual leído, especialmente ceros iniciales. No usar la base habitual.
2. Comprobar permiso inicial/denegado, lectura, cancelación, segundo plano,
   cierre con permiso pendiente y reapertura; comprobar liberación real de
   cámara y que el siguiente escaneo esté disponible.

No se ejecutó `flutter run` sobre la app habitual ni se modificaron permisos
del sistema. Este pendiente no bloquea el cierre automatizado y permanece sin
aprobar hasta contar con evidencia nativa.
