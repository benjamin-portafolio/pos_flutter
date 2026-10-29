# Búsqueda unificada de Caja

Fecha: 2026-10-29. Entorno: macOS, Flutter 3.41.6 / Dart 3.11.4.

## Comportamiento

- Caja presenta un campo único y conserva el acceso a cámara. En macOS,
  Windows y Android el campo recibe foco automáticamente y acepta código +
  Enter mediante el controlador FIFO existente. En Android inicia sin teclado
  virtual y mantiene el botón para alternarlo. El campo unificado sustituye el
  anterior interruptor opcional de macOS: ahora también se prepara automáticamente.
- El foco automático no navega. Tocar el campo abre `ArticleSearchScreen` con
  el texto que hubiera escrito el usuario. Las plataformas sin acceso HID de
  Caja conservan su acceso textual y a cámara mediante `ArticleSearchBar`.
- La configuración `cajaBarcodeSearch` habilita coincidencias inmediatas por
  producto, variante y fragmentos del código. Los consumidores ajenos a Caja
  conservan la búsqueda textual anterior y su navegación.
- Enter sobre un código exacto usa `SaleBarcodeReadCoordinator`, incluidos
  selector, cantidad, pesaje, asignación y alta existentes. Los nombres,
  incluidos los numéricos, y los códigos parciales conservan sus resultados.
  Un código exacto tiene prioridad sobre un nombre numérico coincidente.
  Una entrada numérica sin coincidencias ofrece el flujo de código desconocido.
- Seleccionar un mosaico agrega y permanece en búsqueda. El agregado correcto
  por código vuelve a la misma instancia de Caja después de resolver la cola.
  Cancelaciones y errores permanecen en búsqueda con su resultado visible.
- El botón izquierdo del campo, el inferior y el regreso del sistema usan la
  misma barrera de finalización. No se crean rutas nuevas de Caja.
- Se conservan las pausas, la reanudación explícita por interrupciones, los
  errores sin reintento y la separación entre guardar un código/producto y
  agregarlo a la venta. Un comando que termina en segundo plano no dispara
  el regreso automático hasta reanudar explícitamente.
- El catálogo expone el barcode ya persistido como `String` en
  `VarianteListado`; conserva ceros iniciales. No hay cambios de esquema,
  comandos, eventos ni sincronización.

## Pruebas

`test/presentation/pages/caja/unified_search_test.dart` cubre:

1. Un solo campo, foco inicial sin navegación, traslado del texto, búsqueda de
   pan, selección manual, código de leche, regreso y siguiente lectura.
2. Coincidencias parciales, Enter sin agregado para fragmentos/nombres/nombres
   numéricos, prioridad del código exacto y ceros iniciales.
3. Seleccionar un resultado parcial sin abandonar el buscador.
4. Ambos botones regresan a la misma instancia de Caja y conservan el ID de venta.
5. Cancelar selección/cantidad y fallar al agregar conserva la búsqueda.
6. Regreso explícito y automático con cola aceptada, conservando orden.
7. Guardado en segundo plano, reanudación explícita y recuperación de foco.

`physical_barcode_assignment_test.dart` añade cobertura desde el buscador de
alta de producto, asignación correcta, cancelación del aviso/selector/confirmación
y código guardado con agregado fallido sin reintento. Las pruebas existentes
conservan los recorridos de unidades, pesaje simulado, cola, cambios de venta,
foco y ciclo de vida en las plataformas configuradas. En particular,
`caja_tabs_test.dart` verifica que cambiar de pestaña espera al lector y que
la siguiente lectura se agrega a la nueva venta sin mezclar ambas compras.

`article_search_item_test.dart` comprueba código parcial, ceros iniciales,
combinaciones de producto/variante/código y habilitación explícita. La suite de
Artículos sigue comprobando nombres con mayúsculas y acentos y los demás
consumidores del buscador.

Comandos de verificación:

```sh
dart analyze
flutter test test/presentation/pages/caja/unified_search_test.dart test/presentation/pages/caja/physical_barcode_reader_test.dart test/presentation/pages/caja/physical_barcode_assignment_test.dart test/presentation/pages/articulos
flutter test
```

Resultado del análisis: **sin incidencias**. Suite enfocada sobre la versión
final: **206 pruebas aprobadas**. La ejecución completa final de `flutter test`
terminó con **3000 aprobadas, 27 omitidas y 3 fallidas**; las tres son las
reproducidas sobre el código original y descritas abajo.

Las ejecuciones finales se hicieron sin cambios de fuente durante cada comando.
El archivo `pubspec.lock` del proyecto se conserva sin cambios; el SDK local
resolvió sus dependencias de pruebas también para la copia de comparación.

## Fallos preexistentes

Se ejecutaron también los dos archivos afectados sobre una copia limpia de
`git archive c5f6a9e`, con el mismo SDK y dependencias resueltas localmente.
Reproduce los mismos tres fallos:

- `caja_screen_test.dart`: «caja muestra líneas, cantidades e importes y deja
  acciones pendientes deshabilitadas». Espera dos textos `$109.00`; encuentra uno.
- `weighing/sale_barcode_weighing_test.dart`: «search weighs and accumulates in
  persisted draft, grams=false» y su variante `grams=true`. Tras limpiar la
  búsqueda, `tap(find.byType(Card))` encuentra cinco mosaicos.

No se modificaron esas expectativas para ocultar los fallos. En el archivo de
pesaje solo se retiró el argumento de configuración eliminado del lector.

## Límites

Esta verificación usa SQLite aislado, eventos/comandos reales y entradas,
plataformas, cámara y báscula simuladas. No verifica físicamente un lector HID
ni una báscula. Permanecen los pendientes físicos y límites documentados en
`weighing_windows_verification.md`.
