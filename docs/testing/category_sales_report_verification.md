# Informe de ventas por categoría

Fecha: 2026-10-29.

## Recorrido y alcance

Informes → Ver informe por categoría → categoría → artículo/variante → aporte
por venta o ajuste → recibo existente → Volver al reporte.

Incluye período y flechas, gráfica de dona por importe, participación sobre ventas
netas, orden de variantes por importe o cantidad y beneficio bruto para el período,
la categoría y la variante. Reutiliza el selector de fechas y la tarjeta existente
de beneficio bruto. No modifica tablas, eventos ni sincronización.

## Criterios

- Por decisión del usuario, la clasificación usa la categoría **actual** del
  catálogo. La pantalla explica que mover un producto reclasifica sus ventas.
- Las variantes ausentes del catálogo activo se agrupan en «Fuera del catálogo
  actual»; las disponibles sin categoría, en «Sin categoría». No se descartan sus
  importes. Nombres, precios y costos provienen de las líneas históricas.
- Ventas según fecha local; devoluciones/anulaciones según fecha de negocio y
  las mismas exclusiones (`conflict`, `rejected`) del calculador de informes.
  Se incluyen ajustes de ventas originales anteriores al período.
- Los importes y beneficios se acumulan con `BigInt`. El costo medido conserva
  el redondeo half-up existente. Ajustes restan importe y costo recuperado.
- Costo cero es conocido. Costos ausentes producen beneficio parcial o no
  disponible; no se presentan como costo cero.
- Cantidad neta descuenta ajustes. El orden por cantidad se aplica dentro de
  cada unidad; piezas y medidas no se suman ni comparan entre sí. Se separan
  variantes con unidades/factores históricos distintos.
- Porcentajes de participación solo cuando el total neto es positivo. La dona
  representa importes positivos; los negativos se conservan en la lista y se
  indica su exclusión de la gráfica.
- Cada aporte permite consultar su recibo completo; el importe mostrado antes
  de abrirlo corresponde solo a la variante, no al total del ticket.

## Verificación automatizada

- `category_sales_report_test.dart`: reclasificación, catálogo ausente,
  separación de variantes, ajustes de ventas anteriores y exclusiones,
  conciliación con ventas/beneficio existentes, costos cero/desconocidos,
  costo medido, límites de fechas, precisión y sumas de los desgloses.
- `category_sales_report_screen_test.dart`: recorrido hasta ticket y regreso,
  orden, catálogo reactivo, errores/reintento, fechas/vacío y teléfono de
  320 px con texto a 1.8.
- `reports_screen_test.dart`: acceso con período seleccionado y regresiones
  de Informes.

Resultados: `dart analyze` sin incidencias; las 14 pruebas del conjunto nuevo
más `reports_screen_test.dart` aprobadas. La verificación automatizada no
acredita una prueba manual en dispositivo.

Suite global `flutter test`: 3051 aprobadas, 27 omitidas y 3 fallidas.
Los fallos corresponden a `caja_screen_test.dart` (conteo de textos del total)
y dos casos de acumulación de `caja/weighing/sale_barcode_weighing_test.dart`.
Son los mismos casos documentados previamente en
`sales_time_report_verification.md`; no se modificaron esos recorridos.
No hubo fallos del informe por categoría ni del resto de Informes en esta
corrida global.
