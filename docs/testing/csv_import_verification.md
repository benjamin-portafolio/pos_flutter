# Verificación de importación CSV

Actualización: 2026-11-10.

## Formato actual: oferta y eliminación

```csv
product_id,variant_id,categoria,nombre_articulo,tipo_venta,unidad_venta,nombre_variante,precio_venta,precio_coste,seguimiento_existencias,existencias,codigo_barras,precio_oferta,eliminar_producto
,,,Producto nuevo,unidad,,,25,,no,0,,20,
P_EXISTENTE,V_EXISTENTE,,Producto existente,unidad,,,25,,no,0,,,
P_ELIMINAR,,,,,,,,,,,,,si
```

Los IDs del ejemplo deben sustituirse por IDs reales exportados. La segunda fila
de datos retira oferta, categoría y barcode, y deja costo desconocido; se revisan
las diferencias antes de confirmar. La tercera elimina el producto completo por
ID, sin exigir datos comerciales. `catalogo_columnas.csv` se genera desde
`ArticuloCatalogCsv.notasColumnas()` y documenta las 14 columnas nuevas.

Se mantienen los contratos anteriores exactos de 10, 12 y 14 columnas con
`accion_oferta`. Sin columnas de oferta se conserva; con acción se mantienen las
reglas originales. El nuevo vacío retira. No se aceptan encabezados ambiguos.

Pruebas nuevas en `articulo_import_identity_test.dart` y
`articulo_import_deletion_test.dart`: igualdad/cambio/retirada de oferta,
ausencia de columna, acciones legadas, altas, validación de importes, IDs,
pertenencia, eliminación de múltiples variantes, campos vacíos, contradicciones,
base obsoleta, producto inactivo, rollback y exportación/importación intacta.
Los ensayos usan SQLite aislado en standalone y server_sync; comprueban
`not_required` sin event_refs y `pending` con referencias, respectivamente.

## Verificación de esta actualización (2026-11-10)

- `dart analyze`: **No issues found!** en la revisión final.
- Suite enfocada final: **237 aprobadas**, sin fallos:

  ```sh
  flutter test test/data/local/import test/data/local/export/drift_articulo_catalog_export_service_test.dart test/application/import test/application/commands/articulos/offer_catalog_test.dart test/presentation/pages/gestion_inventario/carga_masiva test/architecture/import_boundaries_test.dart --reporter expanded
  ```

  Incluye 15 pruebas de integración de eliminación: ambos modos, producto con
  dos variantes, fila comercial vacía, evento/referencias/estado de entrega,
  base obsoleta, producto inactivo, rollback después de proyección, rollback
  del lote mixto y rechazo de historial standalone en server_sync. Los tests
  de parser cubren la oferta nueva y los formatos legados; revisión visual por
  widget muestra el producto completo y ambas variantes.
- `flutter test --reporter expanded`: ejecución global finalizada en 4:48,
  **3343 aprobadas, 36 omitidas y 5 fallidas**. Cuatro fallos corresponden a
  `offer_catalog_test.dart` (expectativas anteriores de exportación/acción,
  en ambos modos). Se ajustaron durante esa ejecución: la prueba del formato
  actual usa oferta sin acción y la de acciones construye explícitamente el
  encabezado legado. Las cuatro pasan en la suite enfocada final de 237.
  La ejecución global no se repitió tras ese ajuste.
- El quinto fallo global es `product_supplier_ui_flow_test.dart`, caso
  «seleccionar, guardar, reabrir, cambiar precio y retirar último desde UI»:
  `pumpAndSettle timed out` en el helper `click`, llamado desde la línea 272.
  Ese flujo no se modificó; no se declara verde la suite global ni se atribuye
  el timeout a una causa no investigada.
- `git diff --check`: sin errores. Sin cambios de tablas para esta tarea,
  no se necesita regenerar Drift. Se conservan los cambios locales previos del
  proyecto, incluidos los de recuperación y sus fixtures.

## Archivos de esta actualización

Producción:

- `lib/application/import/articulo_csv_contract.dart`: cuatro encabezados explícitos.
- `lib/application/import/articulo_import_eliminacion.dart`: producto completo y líneas revisadas.
- `lib/application/import/articulo_catalog_import_service.dart`: clasificación/conteos de eliminaciones.
- `lib/application/import/articulo_import_batch_service.dart`: ejecución y reporte por lote.
- `lib/application/import/articulo_import_progreso.dart`: conteo de eliminados.
- `lib/application/commands/articulos/producto_command_service.dart`: eliminaciones en la transacción existente del lote.
- `lib/application/commands/articulos/producto_import_lote_result.dart`: resultado de eliminaciones.
- `lib/data/local/import/articulo_import_csv.dart`: oferta nueva, identidad, agrupación y contradicciones.
- `lib/data/local/export/articulo_catalog_csv.dart`: catálogo, plantilla y notas de columnas.
- `lib/presentation/pages/gestion_inventario/carga_masiva/bulk_import_review.dart`: instrucciones y productos completos a eliminar.
- `lib/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen.dart`: integración de confirmación y aplicación.
- `lib/presentation/pages/gestion_inventario/carga_masiva/bulk_import_progress.dart`: progreso de eliminaciones.

Pruebas:

- `test/data/local/import/articulo_import_identity_test.dart`.
- `test/data/local/export/drift_articulo_catalog_export_service_test.dart`.
- `test/application/import/articulo_import_deletion_test.dart` (nuevo).
- `test/application/commands/articulos/offer_catalog_test.dart`.
- `test/presentation/pages/gestion_inventario/carga_masiva/bulk_import_review_test.dart` (nuevo).
- `test/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen_test.dart`.
- `test/presentation/pages/gestion_inventario/carga_masiva/bulk_import_persistence_test.dart` (conservando modificaciones locales previas).
- `test/presentation/pages/gestion_inventario/inventory_management_screen_test.dart` (firma del doble de pruebas).

Documentación: este archivo y `docs/offer_pricing_catalog.md`.
No se modifican backend, protocolo remoto ni tablas Drift para este cambio.

La evidencia anterior se conserva abajo como registro de la revisión del parser
(2026-10-21); no describe por sí sola el resultado de la suite actual.

## Comportamiento

- Detecta coma o punto y coma comparando los encabezados del contrato de 10/12
  columnas y hasta 20 registros de datos. El encabezado tiene prioridad.
- Revisa la sintaxis y el número de columnas de **todos** los registros antes de
  consultar el catálogo. Un error estructural rechaza el archivo entero, incluso
  cuando la interfaz permite importar solo productos con datos de negocio válidos.
- Usa un parser de estados sobre el texto completo, sin dividir por líneas ni
  reemplazar delimitadores. Respeta comillas, comillas escapadas, campos vacíos y
  saltos de línea citados. Rechaza comillas incompletas o mal colocadas.
- Admite UTF-8 con/sin BOM y CRLF/LF. Mantiene los campos como texto, incluidos
  códigos de barras con ceros iniciales.
- En caso de empate en la detección, la pantalla ofrece coma o punto y coma y
  repite la validación completa. La elección se conserva al confirmar la carga.
  Elegir un delimitador nunca permite saltarse la validación del encabezado.
- Conserva las reglas numéricas existentes: precios y cantidades admiten coma
  decimal dentro de un campo. En CSV por comas debe estar entre comillas. Los
  formatos no admitidos, como `1.234,50`, siguen produciendo errores de negocio.
- No cambia comandos de guardado, lotes, eventos, sincronización, event_refs ni
  esquema Drift. La exportación continúa generando CSV por comas.

## Archivo de referencia

Se leyó `C:\Users\Benjamin\Downloads\Verdura.csv` como UTF-8 mediante Dart y se
procesó con el importador real, sin abrir una base de datos. Resultado:
**52 registros, 10 columnas en todos, 52 filas válidas y cero errores**.

El catálogo simulado contenía la categoría `verdura` y unidades `piece`/`kg`.
También se verificó que la ausencia de la categoría produce el error habitual.
Esto valida el archivo frente a ese catálogo simulado; en un catálogo real siguen
aplicándose las comprobaciones existentes de categorías, nombres e identidades.
Los programas temporales de comprobación se eliminaron.

## Pruebas

- `dart analyze`: **No issues found!**
- Suite enfocada: **174 pruebas aprobadas**:

  ```powershell
  flutter test test/data/local/import test/application/import test/presentation/pages/gestion_inventario/carga_masiva test/architecture/import_boundaries_test.dart --reporter expanded
  ```

  Incluye ambos delimitadores, 10/12 columnas, BOM, LF/CRLF, separadores y saltos
  citados, escapes, vacíos, ceros iniciales, errores numéricos, comillas inválidas,
  estructura inconsistente, selección de delimitador y rechazo sin lecturas ni
  escrituras SQLite. Los tests de lotes/persistencia cubren ambos modos y sus
  eventos/event_refs existentes.

- `flutter test --reporter expanded`: suite global ejecutada, **sin cierre verde**.
  Esa ejecución registró 2640 aprobadas, 24 omitidas y 76 fallidas. Dos fallos eran
  de las pruebas nuevas de interfaz por buscar un botón aún no construido por la
  lista desplazable: se corrigió el desplazamiento de las pruebas y ambas pasan
  en la suite enfocada final. No se repitió toda la suite global después.
  Los demás fallos observados incluyen fixtures externos con rutas de macOS
  inexistentes en Windows, borrado de bases temporales bloqueadas, impresión y
  pruebas de interfaz de Caja/proveedores. No se modificaron esos módulos.
- `git diff --check`: sin errores.
- Sin cambios de tablas: no se requiere regeneración Drift.

## Archivos modificados

Producción:

- `lib/data/local/import/csv_records_parser.dart`: nuevo parser CSV de texto.
- `lib/data/local/import/articulo_import_csv.dart`: detección y validación estructural completa.
- `lib/application/import/articulo_catalog_import_service.dart`: selección opcional y estado de ambigüedad.
- `lib/application/import/articulo_import_solicitud.dart`: propaga la ambigüedad antes de consultar el catálogo.
- `lib/application/import/articulo_import_preparation_service.dart`: propaga selección y reporte.
- `lib/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen.dart`: elección mínima del separador, revalidación y ayuda de UTF-8.

Pruebas:

- `test/data/local/import/csv_records_parser_test.dart` (nuevo).
- `test/data/local/import/articulo_import_csv_test.dart`.
- `test/data/local/import/articulo_import_identity_test.dart`.
- `test/data/local/import/drift_articulo_import_preparation_test.dart`.
- `test/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen_test.dart`.

Los tests anteriores que admitían importación parcial con columnas inconsistentes
se actualizaron al bloqueo estructural solicitado. Los errores de negocio
conservan su tratamiento anterior.

`pubspec.lock` ya tenía cambios al iniciar la tarea; no se agregaron dependencias.

## Evidencia local

Logs completos conservados fuera del repositorio en:

C:\Users\Benjamin\AppData\Local\Temp\pos_csv_verification_20261021_fm8fel45
