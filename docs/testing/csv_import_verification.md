# Verificación de importación CSV

Fecha: 2026-10-21.

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
