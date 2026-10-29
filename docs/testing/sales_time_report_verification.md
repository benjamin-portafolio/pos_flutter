# Reporte temporal de ventas

Fecha: 2026-10-29.

## Recorrido

Informes → Ventas totales / Ver reporte de ventas → Cada hora, Día de la
semana o Mensual → grupo → venta → recibo existente → Volver al reporte.
El selector de fechas y las flechas reutilizan los períodos actuales de Informes.

El reporte consulta `ConfirmedSaleRepository`; no crea eventos, cambia tablas
ni inicia servicios remotos. Conserva el resto de los reportes.

## Criterios de lectura

- Importe neto: ventas confirmadas menos ajustes admitidos por el calculador
  existente. Incluye ventas a crédito; no representa únicamente dinero recibido.
- El período incluye ambos días, en hora local.
- Cada hora agrupa horas locales de todos los días del período.
- Día de la semana reúne lunes a domingo dentro del período seleccionado.
- Mensual conserva mes y año para distinguir períodos de varios años.
- Gráfica y lista se ordenan por importe neto descendente; empates por clave
  temporal ascendente. Solo aparecen grupos con operaciones.
- Ajustes: fecha de negocio para seleccionar período, día y mes; hora local de
  ocurrencia para la agrupación horaria. Se explica en la pantalla.
- El detalle muestra ventas y ajustes separados, incluso cuando la venta original
  pertenece a otro período. Ambos permiten consultar el recibo de la venta.
- Importes negativos se muestran con signo y barra roja. El porcentaje se omite
  cuando el total neto es cero o negativo.

## Verificación automatizada

- `sales_time_bucket_test.dart`: hora local/UTC, repetición de horas y días,
  orden, meses de distintos años, límites inclusivos, ajustes de ventas anteriores,
  exclusión de ajustes rechazados/conflictivos, totales negativos y precisión.
- `sales_time_report_screen_test.dart`: navegación al grupo y ticket, regreso,
  agrupaciones, fechas, actualización reactiva, vacío/error/reintento y teléfono
  de 360 px con texto a 1.8.
- `reports_screen_test.dart`: acceso desde Ventas totales y regresiones existentes.

Resultados: `dart analyze` sin incidencias;
`flutter test test/presentation/pages/informes`: 102 pruebas aprobadas.
También se ejecutó `flutter test` para revisar la suite global.

La suite global detecta además fallos fuera de este reporte en
`caja_screen_test.dart` (cantidad de textos con el total) y
`sale_barcode_weighing_test.dart` (dos casos de acumulación). No se modifican
esos recorridos en este cambio. La verificación es automatizada; no acredita una
prueba manual del reporte en un dispositivo.
