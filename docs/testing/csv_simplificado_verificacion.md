# CSV simplificado de productos

La plantilla descargable y el catálogo exportado comparten el formato público
simplificado. Se identifica por el encabezado exacto, sin `version_csv` visible.
No cambia el esquema SQLite/PostgreSQL ni los contratos de eventos.

```csv
product_id,variant_id,categoria,nombre_articulo,tipo_venta,unidad_venta,nombre_variante,precio_venta,precio_oferta,precio_coste,seguimiento_existencias,existencias,existencias_objetivo,codigo_barras,proveedor_actual,eliminar_variante
```

- Ambos IDs vacíos crean productos. Ambos IDs exportados identifican ediciones;
  los nombres y barcodes no sustituyen la identidad del producto/variante.
- `precio_oferta` vacío retira la oferta; debe ser positivo y <= precio de venta.
- `existencias` inicializa inventario en altas; en ediciones es informativa.
- `existencias_objetivo` usa la misma unidad de inventario que `existencias`,
  aunque la unidad de venta sea distinta. En kg, `1.5` representa 1.5 kg y se
  convierte internamente a 1500 átomos. Cero es válido; vacío conserva y
  `RETIRAR` elimina el objetivo. No mueve inventario ni sustituye el mínimo.
- `proveedor_actual` vacío conserva; un nombre identifica un proveedor existente
  asociado a la variante con cotización válida; `RETIRAR` elimina la asignación.
  No crea proveedores, relaciones ni precios. Nombres se comparan con NFKC,
  trim y minúsculas. El mismo nombre del actual conserva su ID incluso ante
  homónimos; cualquier otra coincidencia múltiple se rechaza. Para sustituirlo
  por un homónimo, distinguir primero los nombres o usar la app/formato antiguo.
- Un proveedor cuyo nombre literal es `RETIRAR` se exporta como `=RETIRAR`;
  nombres que empiezan con `=` llevan otro `=`. El importador elimina solo ese
  primer carácter de escape al resolver el nombre.
- Configurar proveedor u objetivo requiere variante existente. El objetivo
  requiere unidad de inventario disponible y se revalida al aplicar, incluida
  concurrencia posterior a la revisión. Una configuración dormida sin unidad se
  exporta con objetivo vacío y se conserva al editar otros datos.
- `eliminar_variante=si` retira solo esa variante; debe quedar otra activa y se
  deben vaciar proveedor/objetivo de la fila. Omitir filas no elimina nada.
- Esta plantilla no permite cambiar seguimiento en variantes existentes,
  seleccionar un recurso ni eliminar productos completos. Esas operaciones
  mantienen sus accesos en la aplicación y contratos CSV históricos.
- Se mantienen BOM UTF-8, separadores coma/punto y coma, comillas CSV, límite de
  500 filas, revisión previa, exclusión de productos con errores y lote atómico.

## Compatibilidad y pruebas

Se conservan los formatos de 10, 12, 14 y 16 columnas históricos y el v2 de 22
columnas. Las 16 columnas históricas y las 16 simplificadas se distinguen por
sus nombres/orden completos. Las pruebas de eliminación histórica y reposición
v2 usan una fixture explícita en `test/support/catalogo_csv_v2_fixture.dart`.

`test/application/import/articulo_csv_simplificado_test.dart` cubre ambos modos:
altas desde plantilla real, precios, proveedor por nombre, duplicados, escapes,
conversión kg con venta en g, conservar/retirar/cero, saldo/mínimo/cotizaciones,
configuración dormida, retiro de variante, encabezados inválidos y unidad
modificada entre revisión y aplicación. Verifica `not_required` sin event_refs
en standalone y eventos pendientes con referencias en server_sync.

La regresión también abarca importación/exportación previas, precios de oferta,
actualización CSV en disco, eliminaciones legadas, lotes y reposición v2.

## Resultado de verificación — 2026-11-20

- `dart analyze`: sin incidencias.
- Regresión enfocada de importación/exportación, lotes, actualización en disco,
  oferta y reposición: 273 pruebas aprobadas, sin omisiones.
- Interfaz de carga masiva: 41 pruebas aprobadas, incluidas revisión del proveedor
  por nombre y accesibilidad por desplazamiento de las instrucciones.
- Las 22 pruebas del formato simplificado en ambos modos están incluidas en las
  273 anteriores; no se suman de nuevo. Total único del alcance: 314 aprobadas.
- La prueba ajena `physical_barcode_assignment_test.dart`, «segundo plano conserva
  asignación y exige reanudar antes de agregar», falla esperando una partida y
  recibiendo dos. Se reprodujo igual en el árbol modificado y en una copia aislada
  del commit anterior `d8c2c83347b8f6657b0bb26d2b6b76beb709998f` obtenida con
  `git archive`, usando el mismo SDK y dependencias. No se cambió ese flujo.
- Suite general final (`flutter test --reporter expanded`): 3532 aprobadas,
  41 omitidas por requerir entornos de integración HTTP/PostgreSQL aislados y
  1 fallo previo de Caja, el reproducido arriba. No quedaron fallos nuevos del
  alcance CSV. No se acredita ejecución de las 41 integraciones omitidas.
