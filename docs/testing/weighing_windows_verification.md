# Básculas Windows: verificación de sesiones 1–5, 2026-10-20

Implementación local de contratos, parser BAR-8RS, transporte serial Windows y
sesiones exclusivas. Base: `62204fb8b231c469a31eab46c5933d4529e55c47`;
entrega sin commit. La configuración y su verificación de sesión 2 se registran
al final de esta guía. La sesión 3 entregó la ventana; la sesión 4 conecta el lector físico Windows.
Ver resultados y límites de cada sesión al final.
No hay cambios de Drift, eventos, impresoras,
servidor ni dependencias.

El registro completo está en
`G:/Mi unidad/Projects/POS/analisis/08 - Roadmap/Basculas y pesaje en caja/Evidencia/2026-10-20-sesion-1`.
La continuidad, matriz y guía del vault distinguen cada parte pendiente.

## Contratos y uso

- `lib/application/weighing`: `ScaleDevice`, `ScaleProfile`,
  `ScaleSerialSettings`, `ScaleWeight`, `ScaleMeasurement`, errores tipados,
  `ScaleGateway`, `ScaleSessionSnapshot`, `ScaleSession` y
  `ScaleSessionService`. Dart puro. Cantidades exactas con BigInt, gramos
  representables y reloj monotónico inyectable; sin aritmética monetaria.
- `lib/data/weighing`: `RhinoBar8RsProtocol`, `WindowsScaleGateway` y acceso
  Win32 encapsulado en `windows_scale_native.dart`.
- `lib/core/di`: un gateway y un servicio compartidos, ambos lazy. Resolverlos
  no enumera ni abre puertos. El reinicio drena la sesión antes de sustituir
  dependencias; un cierre fallido conserva el propietario y bloquea el reinicio.

La siguiente sesión debe enumerar mediante `ScaleGateway.listDevices()` por
acción explícita, elegir modelo/puerto y conservar `systemId`. El perfil recibe
parámetros, puerto y modelo; CH340 no selecciona el modelo. Se valida identidad
antes de abrir, sin buscar automáticamente otro COM si cambia el destino.
Una actualización de puertos durante conexión abierta devuelve Ocupada sin
interrumpir las consultas del propietario activo.
El identificador PnP disponible depende de la ubicación USB, no es un número de
serie único: no demuestra identidad frente a otro CH340 idéntico en esa ubicación.

`ScaleSessionService.open(profile, owner: ScaleSessionOwner.test/sale)` devuelve
una sesión inmediatamente, incluso durante conexión. Observar `snapshot` y
`updates`; comprobar `hasFreshWeight` para frescura. `close()` invalida el peso
inmediatamente y solo completa con éxito tras el cierre nativo. Conservar y
reintentar ese cierre si falla; no sustituir el servicio para evadir su exclusión.
Cada sesión tiene identidad y flujo propios; comienza sin peso y descarta la
respuesta de cualquier operación que termine después de solicitar su cierre.
La futura UI todavía debe congelar la muestra efectivamente presentada y gestionar
foco/rutas: esta sesión no implementa aceptación ni lifecycle de ventanas.

## Backend y cierre

Se eligió Win32 directamente, con `ffi` 2.2.0 ya instalado (BSD de 3 cláusulas).
No se instaló una biblioteca serial. Solo usa DLL del sistema: `kernel32.dll`,
`setupapi.dll` y `advapi32.dll`; ninguna DLL adicional de báscula para distribuir.
La licencia de `ffi` se revisó en el paquete instalado.

SetupAPI enumera dispositivos presentes de Ports y lee `PortName`, nombre e
identificador PnP; enumerar no abre el COM. `CreateFileW` solicita acceso
exclusivo. Cada llamada nativa ocurre en un isolate de trabajo. DCB configura
9600/8N1 sin control de flujo, DTR ni RTS; se vacían buffers locales al abrir.
La única escritura serial implementada es `0x50`, consulta documentada de peso.

La E/S síncrona usa COMMTIMEOUTS nativos: lectura en slices de hasta 50 ms,
escritura de hasta 300 ms y recepción por consulta de 700 ms, con máximo de 128
bytes; la última lectura iniciada dentro del presupuesto puede añadir hasta
50 ms. El parser limita cada trama a 64 bytes y descarta íntegramente una trama
dañada, sin aceptar un sufijo numérico tras ruido. Si el parser no produce ninguna
observación, la sesión falla y cierra; no se repite la consulta tras ese timeout.
Los errores de formato producen observaciones inválidas que reemplazan el peso
anterior.

El cierre espera la operación real en curso, y después espera el resultado de
`CloseHandle`. No usa `Future.timeout`, no mata isolates ni interpreta solicitar
cancelación como finalización. Incluso un `CreateFileW` que tarde mantiene la
exclusión hasta retornar y cerrar. Un fallo de configuración conserva el handle
para su cierre; un fallo al cerrar conserva la reserva y permite reintentar.
Win32 5 se informa como `accessDenied`: físicamente también fue el resultado
al intentar abrir un puerto ocupado; no distingue permisos de ocupación.

## Evidencia física

Windows 11 Pro, 10.0.26200; Flutter 3.44.4 y Dart 3.12.2, sin actualizar SDK.
El usuario confirmó BAR-8RS. Se vinculó el USB mediante retirada y reconexión:
desaparecieron todos los puertos y reapareció USB-SERIAL CH340 (COM3),
`USB\VID_1A86&PID_7523\6&822DB66&0&2`, hardware REV_8134,
controlador wch.cn 3.9.2024.9. COM3 es evidencia de este equipo, nunca un valor
de producción. No se registró fotografía ni revisión de la etiqueta/conectores.

| Situación | ASCII recibido | Hexadecimal | Interpretación |
| --- | --- | --- | --- |
| Sin carga | `  0.000 kg\r` | `2020302e303030206b670d` | 0 g, no positivo |
| Pantalla reportada por usuario: 0.278 | `  0.278 kg\r` | `2020302e323738206b670d` | 278 g |
| Carga retirada | `  0.000 kg\r` | `2020302e303030206b670d` | invalida peso previo |
| Servicio Dart; pantalla reportada: 1.076 | `  1.076 kg\r` | `2020312e303736206b670d` | 1076 g |

No se recibieron datos en ventanas de 1,5 s sin petición. Se comprobó consulta /
respuesta con `P` sin terminador añadido, respuesta CR y unidad explícita `kg`.
Las doce consultas iniciales con carga tardaron 46–82 ms hasta CR; la espera de
silencio de la primera captura de cero añade aproximadamente 100 ms a ese log.
El servicio Dart recibió doce muestras de 1076 g, con separaciones de 249–299 ms
en esta medición. Parámetros elegidos: intervalo objetivo de consulta 250 ms,
frescura máxima 2 s. Son márgenes operativos para este equipo, no garantías
metrológicas ni una tasa exacta de presentación.

Se comprobaron físicamente: segundo cliente rechazado (Win32 5), propietarios
test/sale excluyentes en el servicio, cierre durante lectura (84 ms observados),
cierre durante conexión, reapertura, sesión siguiente sin lectura heredada,
retirada USB (error Win32 31, peso invalidado, CloseHandle confirmado), puerto
ausente, identidad distinta rechazada y recuperación posterior con lectura cero.
No se enviaron tara, cero, calibración, precios ni comandos exploratorios.

El fixture `test/fixtures/weighing/rhino_bar8rs_2026_10_20.json` contiene solo
tramas realmente capturadas. Los casos OL/ERROR, negativos, unidades distintas,
overflow y subgramos de los tests son **sintéticos** y no certifican esos formatos
en hardware. Solo `kg` está admitido por el parser inicial. La estabilidad es
`unknown`; no se deduce de repetición de pesos ni del display de la báscula.

## Verificación automatizada y límites

- `dart analyze`: sin incidencias.
- `flutter test test/application/weighing test/data/weighing test/core/di/weighing_dependencies_test.dart --reporter expanded`:
  47 aprobadas. Fragmentación, concatenación, ruido, exactitud, invalidación,
  reloj/temporizador, exclusión, cierre pendiente/fallido, respuestas tardías,
  plataforma sin soporte y DI en ambos modos sin tráfico remoto.
- `flutter test --reporter expanded`: 2528 aprobadas, 73 fallos y 23 omisiones
  existentes de la suite HTTP condicionada por entorno. Sin fallos de básculas.
  Entre los fallos: fixtures con rutas macOS, limpieza de SQLite abierta en
  Windows, subprocesos de reapertura y diferencias de pruebas de interfaz/raster.
  En la corrida final, 72 casos coinciden con fallos reproducidos en HEAD original.
  Un caso de alta de proveedores falla en la suite con `pumpAndSettle timed out`,
  pero pasa aislado en ambas revisiones. La primera corrida tenía también 73
  fallos, con un caso distinto. Ver `baseline_all_cases_comparison.json`,
  `candidate_final_ui_case.txt` y `baseline_final_ui_case.txt`. No se declara verde
  la suite ni se modifican esos flujos para cerrar esta sesión.
- `flutter build windows --debug`: aprobada en copia aislada con los mismos 23
  archivos de código/tests/fixture modificados, verificados por SHA-256. Los
  primeros intentos en el directorio habitual encontraron DLL bloqueadas por
  pruebas y por la app ya abierta. La copia temporal compiló en 94,5 s y la revisión final en 35,1 s; advertencias
  MSB8029 por compilar en Temp. La app del usuario siguió abierta. Evidencia:
  `windows_build_isolated_final.txt`, `build_source_hashes.json`, `build_result.txt`.
  Los 130 paquetes resueltos coinciden con el entorno original; pubspec y lock
  entregados no cambian (`resolved_packages_comparison.json`).
- No procede build_runner: no cambió el esquema.

Pendientes físicos: formatos de negativo/sobrecarga/error y unidad distinta, y
silencio de respuesta con el USB todavía presente. La caducidad temporal sí está
probada con reloj/transporte controlados y la desconexión está comprobada en
hardware. La aceptación de una ventana, configuración persistida y el flujo de
Caja pertenecen a sesiones 2–4. No se declara cierre global de B01–B38.

## Fuentes

- [Manual Rhino BAR-8RS, copia del documento del fabricante](https://ferremobil.com/pdf/_001/21BAS016430_001.pdf):
  sección de conexión serial, 9600/8N1 y consulta `P` (80 decimal / 50 hexadecimal).
  SHA-256 de la descarga revisada:
  `7DDA262F44C53FD9FFD179C65CFB1242424663450770FCC66AD161AF4EF3E01C`.
  La descarga actual enlazada por Rhino redirige a autenticación SharePoint;
  el formato de respuesta se verifica con capturas propias.
- [Microsoft: COMMTIMEOUTS](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-commtimeouts).
- [Microsoft: apertura exclusiva de recursos de comunicación](https://learn.microsoft.com/en-us/windows/win32/devio/communications-resource-handles).
- [Microsoft: cancelación de E/S pendiente](https://learn.microsoft.com/en-us/windows/win32/fileio/canceling-pending-i-o-operations).

## Sesión 2: configuración local — 2026-10-20

`Configuración → Básculas` está disponible en ambos modos junto a Impresoras.
Permite varios perfiles, editar/quitar y elegir/cambiar/quitar la predeterminada.
La primera alta no elige ninguna; quitar el perfil predeterminado deja la
selección vacía. Solo se ofrece Rhino BAR-8RS. No hay cambios de ventas, Drift,
eventos, impresión ni servidor.

`ScaleSettings`, `ScaleSettingsStore`, `ScaleSettingsException` y
`ScaleSettingsController` viven en `lib/application/weighing`.
`lib/data/local/weighing/scale_settings_file_store.dart` escribe
`scale_settings.json`, versión 1, en el directorio de soporte de la instalación.
Persiste ID de perfil, alias normalizado, COM, identidad PnP, modelo y parámetros
seriales de sesión 1. ID y destino COM son únicos; la predeterminada debe existir.
Las operaciones se serializan y publican solo tras confirmarse la escritura.

El archivo se reemplaza mediante temporal en el mismo directorio, flush y rename,
sin borrar el confirmado antes. Corrupción, UTF8 inválido o versión desconocida
bloquean guardados normales y conservan el original. Recuperar exige confirmación
en UI y copia el original a `.preserved-*` antes de crear ajustes vacíos. Un fallo
de lectura ofrece recargar, sin ofrecer reset; un fallo de guardado conserva el
estado confirmado. También se probaron reemplazo y recuperación fallidos con el
archivo abierto sin permiso de eliminación en Windows.

`scale_settings_screen.dart`, `scale_profile_dialog.dart` y
`scale_test_screen.dart` separan lista, formulario y prueba. La enumeración es
explícita con Actualizar puertos. Si el destino desaparece o cambia COM, el
formulario exige reselección, sin identificar un modelo por CH340. Un perfil
guardado sigue sujeto a la comprobación nativa de COM+systemId antes de abrir.
La identidad PnP por ubicación conserva el límite de sesión 1 frente a otro
adaptador idéntico en la misma ubicación.

La prueba usa `ScaleSessionOwner.test`, muestra peso/unidad exactos y errores,
sin escrituras de negocio. Salir, perder foco/actividad o cubrir la ruta invalida
inmediatamente la muestra y solicita cierre. La navegación normal espera el
cierre; si falla, conserva la reserva y ofrece reintento. Volver requiere Reanudar
prueba y empieza sin lectura anterior. Una retirada externa del widget solicita
cierre igualmente. El singleton conserva un cierre fallido, y Configuración puede
reintentarlo. Una prueba que encuentra otro propietario informa Ocupada y no lo
cierra.

`ScaleSessionService.withIdleResource` protege el reemplazo asíncrono de ajustes:
no admite sesiones mientras se guarda/recupera ni mutaciones mientras existe una
sesión, incluido su cierre pendiente/fallido. Los perfiles de sesión son snapshots
inmutables. DI registra el archivo/controlador y carga ajustes al inicio sin
enumerar ni abrir COM; disponer/reiniciar drena operaciones y libera suscripciones.
La prueba de DI comprueba recarga en ambos modos y cero tráfico HTTP.

Verificación automatizada:

```text
dart analyze
flutter test test/application/weighing test/data/weighing test/core/di/weighing_dependencies_test.dart test/presentation/pages/basculas test/presentation/pages/pantalla_principal/menu_lateral_test.dart --reporter expanded
```

Análisis limpio y **95 pruebas aprobadas**, 1 omisión física intencional. Incluye
la regresión de sesión 1 y del menú existente. B09/B11–B14 quedan verificados en
automatización; B07/B10/B15 incluyen concurrencia, cierre, foco/actividad/rutas,
archivo y reselección del destino con dobles.

Suite completa: **2563 aprobadas, 75 fallos y 24 omisiones** (23 HTTP anteriores
y la prueba física optativa). Sin fallos de básculas. Los 73 fallos finales de S1
reaparecen; catálogo vacío de proveedores ya falló en la base de S1 y restore de
mínimos se reprodujo ahora en el HEAD original, mismo `No element` en `_edit:226`.
74 fallos tienen evidencia en base. El caso restante, alta de proveedores,
ya fallaba en suite S1 y pasa aislado en esta revisión y en la base anterior.
No se declara suite verde. Ver `baseline_comparison.json`,
`baseline_minimum_stock_restore.txt`, `candidate_supplier_case.txt` y evidencia S1.

`test/data/weighing/scale_configuration_hardware_test.dart` es optativa:
requiere Windows y variables `SCALE_TEST_PORT` y `SCALE_TEST_SYSTEM_ID` explícitas
del equipo ya identificado. No busca un modelo por nombre ni configura la app
del usuario; crea y elimina un directorio temporal. Ejecutada por separado:
**1 aprobada**. Enumeró el CH340/COM3 de sesión 1, recibió bytes reales
`2020302e303030206b670d` → `0.000 kg`, 0 g/no positivo, comprobó exclusión y bloqueo
de cambios, cierre nativo confirmado, alta sin default implícito y guardado/elección/
reload. Segunda sesión vacía y cierre durante conexión también verificados.
No se volvió a comparar con el display físico ni se certifica calibración.

Parser, gateway y Win32 son idénticos por SHA-256 a sesión 1. No cambió integración
nativa, SDK ni dependencias: no se repitió el build Windows ni procede build_runner.
La compilación aprobada de sesión 1 no se etiqueta como compilación de sesión 2.
Evidencia, logs, resultados globales y manifiesto de fuentes:
`G:/Mi unidad/Projects/POS/analisis/08 - Roadmap/Basculas y pesaje en caja/Evidencia/2026-10-20-sesion-2`.

Pendientes físicos:

1. Recorrido manual visual en Windows de configuración/prueba, foco real y
   edición/eliminación ocupada; renumeración/desconexión/reconexión sin sustitución.
   B10 y B15 físicos permanecen parciales pese a los recorridos automatizados y
   a la prueba real de sus controladores.
2. B04/B05 físicos de sesión 1: formatos de negativo/sobrecarga/error/unidad
   distinta y silencio con USB presente. Las pruebas sintéticas no los cierran.
3. Sesión 3 entrega la ventana descrita debajo. Los lectores de Caja todavía
   no usan pesaje; su integración corresponde a S4.

## Sesión 3: ventana de pesaje en vivo — 2026-10-20

`lib/presentation/pages/caja/weighing/sale_weighing_dialog.dart` y
`sale_weighing_controller.dart` son componentes separados de presentación.
Reciben condiciones inmutables del catálogo, perfil y el servicio compartido de
S1–S2. `watchDraft` crea una consulta observable por diálogo, con valor inicial,
y `loadManualConditions` relee las condiciones al abrir la alternativa manual.
No se añadieron accesos desde HID, cámara, buscador ni edición de líneas.
**La ventana está probada pero todavía sin acceso desde los lectores,
pendiente de sesión 4.**

Muestra producto/variante, referencia real del precio, alias de báscula, peso,
importe y acumulación prevista. Convierte el decimal exacto a gramos enteros,
contrasta los gramos del contrato y usa `InventoryQuantityCodec` para expresar
la cantidad en la unidad del producto. `MeasuredSalePreview` reutiliza
`MeasuredSaleCalculator` y `SaleItemSnapshot.plus`; el total acumulado se
redondea sobre la línea completa. No reconstruye peso desde dinero ni redondea
subgramos hacia arriba. Se invalidan cero, negativos, errores, unidades no
compatibles, subgramos, overflow y caducidad, también sin nuevas tramas.

La política aplicada permite confirmación manual con peso positivo, válido,
representable y reciente. La estabilidad de BAR-8RS sigue siendo `unknown`:
se informa en pantalla y no se infiere de repetición ni del display. No existe
bandera comprobada estable/inestable que se deba simular como soporte físico.
Se conservan consultas de 250 ms y frescura de 2 s del servicio; el reloj
monotónico y el transporte se inyectan allí. No se modifica parser ni transporte.

Un token de revisión se acredita después del frame presentado. Una lectura o
actualización del borrador pendiente de render invalida el token. Enter requiere
una pulsación nueva, ignora repetición y comparte aceptación única con el botón.
El resultado congela `measuredQuantity`, unidad/precio/referencia esperados y
cantidad visible, con `targetAmountMinor = null`. Las respuestas posteriores y
el cierre fallido no cambian esa intención. No se ejecutan comandos desde la
ventana; el consumidor de S4 deberá manejar el rechazo transaccional visible y
conservar las pausas/cola de los lectores.

Cancelar, volver, perder foco/actividad/ruta o retirar el widget descartan la
muestra y solicitan cierre. Una salida normal espera su confirmación; un cierre
fallido conserva la reserva y permite reintentarlo. Volver exige Reanudar y una
lectura nueva. Una interrupción durante un reintento pendiente cancela esa
reanudación aunque el foco regrese antes de terminar el cierre. Captura manual libera primero el puerto, relee condiciones y
abre `SaleQuantityDialog` sin trasladar el peso. Su resultado conserva las reglas
manuales existentes, incluida captura por importe. Ese diálogo no se modificó.

Pruebas nuevas en `test/presentation/pages/caja/weighing`:

- `sale_weighing_controller_test.dart`: 15 casos de exactitud, rechazo,
  caducidad, acumulación, resultado y cierre con gateway/reloj inyectados.
- `sale_weighing_dialog_test.dart`: 14 casos de teclado, render pendiente,
  doble clic, ciclo de vida, conexión/lectura pendiente, cierre fallido,
  alternativa manual y 480×640 con texto 2×.
- `sale_weighing_result_test.dart`: 5 casos contra el comando real y SQLite
  aislada: persistencia de 430 g/$21.50 y rechazos sin escritura por cambios
  de precio, referencia, unidad o modo. Esa escritura solo ocurre en el test.

`dart analyze`: sin incidencias. Regresión focalizada: **156 aprobadas, 1 omisión
intencional de hardware**; incluye S1–S2, DI, diálogo manual y condiciones
obsoletas. Comando exacto, logs, hashes y resultado de la suite completa en
`G:/Mi unidad/Projects/POS/analisis/08 - Roadmap/Basculas y pesaje en caja/Evidencia/2026-10-20-sesion-3`.
No se abrió hardware en S3, no se repitió build Windows y no procede
build_runner: no hubo cambios nativos, de dependencias ni de esquema.

Pendientes:

1. Integrar únicamente los lectores acordados en S4, conservando el único
   comando, cola, pausa, condiciones obsoletas y alternativa manual.
2. Verificar Enter/foco y recorrido con equipo real; B21/B24 físicos siguen
   pendientes. Mantener pendientes físicos de S1–S2 y B38, sin cerrar con fakes.


### Resultado final de suite global S3

`flutter test --reporter expanded`: **2598 aprobadas, 74 fallos y 24 omisiones**
(23 HTTP condicionadas por entorno y 1 prueba física optativa). **Ningún fallo de
básculas/pesaje. La suite global no está verde.** Los 74 casos fallidos coinciden
con casos fallidos de S2; no hubo casos fallidos exclusivos de esta revisión final.
Contraste por nombre de caso: `session2_comparison.json`; detalle en
`failed_cases.txt` y `flutter_test.txt` de evidencia S3. No se corrigieron flujos ajenos.

La corrida previa a la corrección final de ciclo de vida tuvo 2594 aprobadas,
76 fallos y 24 omisiones. Incluyó restore de mínimos serverSync con `No element`
en `_edit:226`, que pasó en la corrida final; no se presenta ese caso como
reproducido en HEAD original. Hay variación entre corridas, como en S1–S2.
B37 sigue sin cierre global. No se atribuye el build de S1 a esta revisión.

## Implementación de sesión 4 — 2026-10-20

Integración HID de Windows implementada, sin habilitar pesaje en buscador ni
edición. Se conservaron los cambios preexistentes S1–S3 y ajenos sobre
`62204fb8b231c469a31eab46c5933d4529e55c47`, sin commit.

### Archivos y comportamiento

- `lib/presentation/pages/caja/weighing/sale_barcode_quantity_dialog.dart`:
  decisión compartida en presentation. Condiciones consultadas del catálogo,
  unidad activa de masa kg/g, Windows con servicio y predeterminada confirmada
  llevan a la ventana existente; sin soporte/default, volumen y cámara siguen
  manual. El perfil se congela antes de esperar catálogo. Una interrupción de
  foco/actividad/ruta durante esa consulta exige Reanudar, sin abrir el puerto.
- `lib/presentation/pages/caja/barcode/physical_barcode_reader.dart` y
  `lib/presentation/pages/caja/sale_barcode_scanner_screen.dart`: usan esa
  decisión dentro de sus wrappers existentes. Cámara declara captura manual,
  conserva parada durante modal y BarcodeReadGate; sin plataforma nueva.
- `lib/presentation/pages/caja/weighing/sale_weighing_dialog.dart`: reutilizada,
  con pausa inicial para consulta interrumpida y rechazo del Enter final de un
  burst HID recibido durante pesaje. Enter sostenido/repetición, revisión de
  frame e intención única conservan las garantías S3. Cierre nativo termina
  antes de devolver intención o pasar a captura manual vacía.
- `test/presentation/pages/caja/weighing/sale_barcode_weighing_test.dart`:
  20 casos nuevos aprobados contra widgets/coordinador/comandos/SQLite reales,
  gateway/teclado/foco simulados. Kg/g, precio por 100 g, dos pesadas agrupadas
  en el mismo borrador, replay y refs de ambos modos, sufijo/cola/cierre,
  cancelación conectando, foco/consulta pendiente, ambiguo, manual y errores.
- `test/presentation/pages/caja/physical_barcode_assignment_test.dart`: conserva
  los dos casos manuales y añade aceptar/cancelar pesaje tras asignar código;
  los cuatro aprobados. Cancelar conserva barcode y comunica Código guardado.
- `docs/testing/weighing_windows_verification.md`: guía actualizada. Evidencia,
  comandos y hashes en [[08 - Roadmap/Basculas y pesaje en caja/Evidencia/2026-10-20-sesion-4/README|registro S4]].

El único guardado sigue siendo `SaleBarcodeReadCoordinator` →
`SaleQuantityFormResult.toCommand` → `VentaBorradorCommandService.agregar`.
No cambian coordinador, comandos, calculadora, payloads, Drift, refs, agrupación,
confirmación, impresoras, servidor o sincronización. El comando conserva
revalidación transaccional de precio/unidad/referencia/modo. Un fallo no
reintenta ni reutiliza el peso; el lector conserva mensajes y pausa actuales.

### Límites y reanudación para sesión 5

1. Win32_SerialPort no enumeró puertos en esta sesión; no se verificó Enter/foco
   con lector y Rhino reales. Mantener B21/B24/B27/B28 físicos y B38 pendientes.
   La automatización usa dobles, sin modificar datos/configuración del usuario.
2. Mantener pendientes físicos S1–S2: negativo/sobrecarga/error/otra unidad,
   silencio con USB enumerado, revisión visual y renumeración/reselección real.
3. S5: conectar equipo identificado, registrar/probar/elegir predeterminada y
   escanear producto de prueba hacia $20; comprobar Enter deliberado, botón,
   cancelación, desconexión, foco real y puerto reutilizable. Contrastar peso e
   importe visibles con borrador/ticket persistidos usando base aislada.
4. Parser, gateway, Win32, servicio y sesión mantienen hashes S3
   (`reused_source_comparison.json`). Sin cambios nativos/dependencias/esquema,
   no se repitió build Windows ni procede build_runner. Compilación y
   distribución de la revisión final y cierre B37/B38 corresponden a S5.


## Regresión focalizada final S4

`dart analyze`: sin incidencias. Comando focalizado de evidencia: **431 aprobadas,
1 omisión intencional de hardware sin variables**; incluye las 20 nuevas de
integración y las 2 nuevas de asignación pesada, no son 431 tests nuevos.
B21/B23–B24/B26–B35 automatizados verificados; componentes S1–S3 y lectores,
asignación, cámara/gate, coordinador, captura manual y ventas medidas aprobados.
La prueba física optativa no se ejecutó: no hubo COM enumerado. B21/B24/B27/B28
físicos, B38 y límites previos siguen pendientes. Evidencia S4/focused_tests.txt.


## Resultado global final S4

`flutter test --reporter expanded`: **2620 aprobadas, 74 fallos, 24 omisiones**
en 5:28 (23 HTTP condicionadas por entorno y 1 prueba física optativa sin
variables). **Ningún fallo de básculas, pesaje o lectores. La suite no está verde.**

73 fallos coinciden con S3. El otro es catálogo vacío de proveedores
(`supplier_local_acceptance_test.dart`), ya fallido en S2 y contrastado con HEAD
original según continuidad S1–S2. Restore de mínimos standalone, fallido en S3,
pasa en esta corrida. No hay casos fallidos exclusivos frente a la unión de
las corridas finales S1–S3. Esto acredita la comparación por nombre de caso;
no se vuelve a certificar cada fallo en HEAD durante S4 ni se corrigen flujos
ajenos. Detalle: `prior_sessions_comparison.json`, `failed_cases.txt` y
`flutter_test.txt` en evidencia S4.

Análisis final sin incidencias y regresión focalizada **431 aprobadas/1 omisión**.
Los 20 casos nuevos de integración y 2 de asignación de pesaje están incluidos
ahí y en la suite completa, sin sumarlos otra vez. `git diff --check` sin errores.
Las corridas parciales de diagnóstico no son resultados finales; los tres logs
iniciales de preparación de tests quedan en `diagnosticos/` solo como contexto.

Sesión 4 queda implementada y verificada automáticamente en su alcance. Para
sesión 5 permanecen: prueba física de Enter/foco/cola y B38 con Rhino y lector,
los límites físicos S1–S2, compilación/distribución de la revisión entregada y
cierre global B37. La compilación S1 no se atribuye a esta revisión. No se cerró
ni relanzó la app del usuario ni se modificaron sus datos o configuración.
## Sesión 5 — verificación y cierre parcial, 2026-10-20

Revisión probada: HEAD `62204fb8b231c469a31eab46c5933d4529e55c47` más el árbol sin
commit, identificado por `source_hashes.json` y `final_tracked.diff` en evidencia
S5. Se preservaron exactamente los ocho archivos tracked ya modificados al
iniciar; también los archivos de S1–S4, salvo los cambios propios indicados aquí.
No se tocaron datos, configuración ni proceso original del usuario.

### Cambios propios

- `windows_scale_native.dart`: resolver e invocar GetLastError antes de las APIs
  que establecen su error, con getter FFI leaf. En un isolate Flutter debug frío,
  la primera resolución borraba ERROR_NO_MORE_ITEMS: enumeración fallaba con
  transportError/nativeCode 0 aunque el test Dart nativo pasara. Se reprodujo
  en ejecutable y se verificó la corrección enumerando y leyendo con el gateway
  de producción. No otra DLL, modelo ni transporte.
- Retirada de `SaleWeighingController.retry()` sin consumidor de producto; el
  test usa stop/start, como el flujo coordinado de UI.
- Dos pruebas nuevas `sale_weighing_ticket_test.dart`, una por modo: muestra
  revisada → comandos → SQLite real → acumulación 830 g/$41.50 → confirmación
  sintética → reapertura → ticket exacto. No compra ni impresión real.
- Documentación y auditoría individual B01–B38 actualizadas. Sin cambios Drift,
  esquema, paquetes, payloads, tara, calibración o sincronización.

### Automatización y build de la revisión entregada

| Verificación | Resultado final | Evidencia S5 |
| --- | --- | --- |
| dart analyze | Sin incidencias | dart_analyze_final.txt |
| flutter test --reporter expanded | 2622 aprobadas, 74 fallos, 24 omisiones, 6:44 | flutter_test_final.txt |
| flutter build windows --debug | Aprobado; última corrida 41.6 s | windows_build_final_after_cleanup.txt |
| Prueba optativa con Win32/Rhino reales | 1 aprobada; 278 g, bytes 2020302e323738206b670d | hardware_configuration_delivered.txt |
| Limpieza rg/diff | Sin diagnósticos, COM de prueba, helpers muertos ni diff con whitespace inválido | cleanup_search_final.txt, final_diff_check.txt |

Ningún fallo de básculas, pesaje o lectores. Los 74 nombres fallidos ya aparecen
en S1–S4: 73 coinciden con S4; restore de mínimos standalone ya falló en S2/S3,
y el alta UI de proveedores fallida en S4 pasó aquí. Comparación por caso en
prior_sessions_comparison.json y session4_comparison.json; no se recertificó
toda la base ni se repararon flujos ajenos. **B37 global sigue abierto.** Las 24
omisiones son 23 HTTP condicionadas por entorno y el caso físico optativo,
ejecutado después por separado. Las 433 focalizadas/1 omisión iniciales preceden
los últimos cambios; la suite final volvió a cubrir todos esos casos.

Build con main.dart normal en copia aislada para no sobrescribir DLL abiertas
de la app del usuario: `.codex-verification/weighing-s5-final`. Las 724 fuentes
y archivos de build coinciden por SHA-256 con el repositorio; mismos paquetes
efectivos. Ver final_build_source_hashes.json, final_resolved_packages_comparison
 y final_windows_bundle_files.json. Báscula usa ffi existente y APIs del sistema
kernel32/setupapi/advapi32; no necesita DLL serial adicional. Dumpbin registra
las DLL normales de Flutter/plugins/SQLite y CRT debug (MSVCP140D,
VCRUNTIME140D/VCRUNTIME140_1D/ucrtbased), presente en este equipo. No se certificó
instalación en máquina limpia, release ni instalador.

### Prueba nativa y física con datos aislados

Instancia completa `PRUEBA BASCULAS S5`, ejecutable y datos fuera del repositorio:
`.codex-verification/weighing-s5-20261020` y `weighing-s5-data`. El entrypoint
archivado como verification_main.dart.txt cambia PathProvider, semilla y título;
usa widgets, gateway, comandos y apertura AppDatabase de producción. No ejecuta
startConfiguredRuntimeServices del main original. El build de entrega anterior
sí usa main.dart normal. Ningún diagnóstico temporal quedó en producción.

Rhino BAR-8RS por CH340, COM3, 9600/8N1, wch.cn 3.9.2024.9, mismo PnP de S1.
Identidad por ubicación USB, sin serie única. Win32_SerialPort no la enumeraba
inicialmente; Get-PnpDevice/SetupAPI sí. No usar solo WMI para declarar ausencia.
La prueba nativa separada verifica exclusión prueba/venta, bloqueo de edición,
CloseHandle, guardar/default/recarga y siguiente sesión vacía.

| Recorrido real | Resultado y evidencia |
| --- | --- |
| Configuración | Enumerar COM3, elegir Rhino, probar 0.438 kg, cerrar, guardar perfil R y elegir default explícitamente. Primera alta sin default implícito. physical_production_reading.jpg, profile_default.jpg. |
| Reinicio | Cierre normal y nuevo proceso; scale_settings idéntico byte a byte, catálogo/metadatos de prueba conservados. AppDatabase y política actual de reinicio, sin borrar una base para preparar la prueba. restart_before/after.json, scale_settings_before/after_restart.json. |
| Apertura | Código 604722012947 por teclado manual + Enter; 0.438 kg/$21.90, cero líneas/eventos antes de aceptar. El Enter del código no aceptó. sale_keyboard_open y journal. |
| Botón | Retirar carga: usuario vio 0.278 kg/$13.90 y pulsó Aceptar. Al volver al chat, intención aún sin comando quedó pausada; Reanudar lector, sin reenviar código/peso, guardó exactamente 278 g/1390 centavos, un evento. button_acceptance_after_resume.json. No reintento de un comando fallido. |
| Enter separado | Usuario vio 0.422 kg/$21.10 y confirmó con Enter nuevo. Misma venta/línea: 278+422=700 g/$35.00, dos eventos. enter_accumulation_persisted.json y captura Caja. |
| Cero/cancelación | Retirar toda carga deshabilitó Aceptar; colocar carga y cancelar conservó 700 g/$35.00 y dos eventos. after_cancel.json. |
| Desconexión | Quitar USB: Aceptar bloqueado, «Se perdió la comunicación con la báscula», puerto ausente. Reconectar y recuperar explícitamente funcionó; cancelar no agregó. usb_disconnected_ui, ports_disconnected/reconnected y after_usb_recovery.json. No se registró el valor numérico de la muestra recuperada. |
| Sin respuesta | Apagar con USB presente: Aceptar bloqueado, «La báscula no respondió. Revisa la conexión». COM3 sigue presente. usb_present_no_response y ports_power_off_check.json. Sin nueva medición de latencia; cadencia S1 vigente. |
| Foco/segundo plano | Volver al chat o minimizar invalida. Usuario confirma restaurar no habilita; Reanudar recibe muestra nueva y Cancelar no agrega. Configuración→Probar lectura también recuperó después de minimizar/restaurar y Reanudar prueba. Journal y configuration_after_manual_resume.jpg (estado posterior). |
| Vista reducida | Usuario confirma peso, importe, mensajes y botones completos; cancela. Captura posterior de Caja 569×714: native_reduced_caja.jpg. Texto 2× verificado por widget vigente a 480×640; no se cambió escala global de Windows. |
| Ticket | Misma venta 6e368230-d103-4089-9e90-8734d92b7190: UI/ticket/SQLite 0.700 kg/$35.00, subtotal/total $35.00. Dos agregados y un venta_confirmada sintético, todos not_required; cero event_refs standalone. native_test_ticket_totals.jpg, native_test_ticket_persisted.json. Sin imprimir, compartir ni compra real. |

Límite de la semilla: primer intento de ticket rechazó variant_id `s5-variant`
por no ser UUID. Se archivó SQLite antes de corregir solamente identificadores
de los datos de prueba y sus referencias (fixture_uuid_correction.json).
Peso, importe, venta y número de agregados permanecieron iguales; luego se
confirmó desde UI/comando/evento de producción. No se cambió código para eludir
validación. La evidencia previa conserva los IDs originales. Este ajuste de
fixture forma parte del límite del ensayo nativo, no es una migración productiva.

El lector real no entregó texto ni en Bloc de notas según el usuario. **Todas
las aperturas físicas S5 usaron teclado manual**, aunque recorren el lector de
Caja. No certifican escaneo HID, su sufijo ni conservación de cola real. Los
intentos iniciales de reanudar Configuración registraron inactive/unfocused;
la pantalla negra correspondió al arnés diagnóstico de ruta única que se retiró.
La repetición manual final en app completa sí recuperó. No se relajó el foco.
Las capturas son estados puntuales; observaciones de interacción se atribuyen
al usuario y se contrastan con SQLite cuando corresponde.

### Estado y siguiente paso exacto

Auditoría individual A/N/F en `Evidencia/2026-10-20-sesion-5/Auditoria B01-B38.md`.
La sesión queda ejecutada con **cierre parcial**, sin compatibilidad física
completa ni plan totalmente cerrado. Pendientes:

1. Reconectar/configurar el lector hasta que escriba 604722012947 y Enter en
   Bloc de notas. Después repetir B21/B27/B28/B38 con HID real: escanear masa,
   comprobar que el sufijo no acepta, aceptar con botón y Enter en capturas
   separadas, encolar [masa,pieza] antes del modal y verificar orden/conservación
   al perder foco, cancelar y volver. No aceptar el teclado manual como sustituto.
2. B15 F: con puerto renumerado, comprobar que exige reselección explícita;
   comprobar edición/baja visual del perfil ocupado. El bloqueo de controlador
   sí tiene evidencia nativa y automatizada. B04 F: negativo/error/otra unidad
   no observados; capturar solo estados reales seguros, sin provocar sobrecarga.
3. Cámara Android/iOS/macOS: regresión automatizada del comportamiento y selección
   de plataforma ejecutada en Windows; no build ni ensayo físico en esos equipos. Si se
   exige aceptación física, ejecutar permisos, cancelación/segundo plano y
   cantidad manual en un dispositivo soportado; no ampliar transporte.
4. B37 global: tratar los 74 fallos existentes en trabajo separado y repetir
   la suite tras corregirlos. No reparar otros agregados para declarar este
   plan cerrado. Build debug local no certifica despliegue en máquina limpia.

Reutilizar parser/cálculos/contratos/regresiones vigentes; repetir solo ante
cambio, fallo o duda concreta. El bundle previo obsoleto se conservó marcado
OBSOLETO-NO-USAR; el entregable vigente es weighing-s5-final. Ensayo y datos
se conservan para reproducir pendientes. No hay commit ni despliegue.
