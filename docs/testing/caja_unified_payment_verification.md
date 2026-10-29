# Cobro unificado de Caja

Verificación automatizada del 29 de octubre de 2026.

## Alcance

Caja abre directamente el cobro en Efectivo mediante el botón Cobrar o un
nuevo Enter con el lector vacío. Un código seguido de Enter conserva la
lectura; las repeticiones físicas del terminador no solicitan cobrar.
El Enter que abrió el cobro no confirma: debe soltarse y pulsarse de nuevo.

Efectivo, Transferencia, Crédito y Tarjeta son pestañas de una sola pantalla.
Cliente, efectivo y referencia se conservan durante esa sesión. Solo se envían
los datos del método activo al comando existente. Tarjeta es una pestaña
informativa solicitada expresamente, sin operación de pago.

El guardado bloquea confirmaciones, pestañas, cliente y salida. Un fallo
conserva la captura y permite un nuevo intento explícito. El comprobante se
abre después de guardar y al cerrarlo se vuelve a Caja. Cancelar el cobro
conserva el borrador. Se retiraron las pantallas separadas de efectivo y
transferencia. Los cambios de producción están limitados a presentación;
no cambian comandos, eventos, esquema ni sincronización.

## Cobertura

- `payment_method_screen_test.dart`: foco inicial y al regresar a Efectivo;
  pago exacto con campo vacío; monto suficiente, insuficiente y fuera de rango;
  Enter de apertura y repetición; conservación de captura y cliente; referencia
  multilínea sin confirmar; Tarjeta sin operación; bloqueo y reintento explícito.
- `cash_payment_content_test.dart`: cambio, faltante, centavos y denominaciones;
  teléfono estrecho con texto grande y teclado.
- `cash_confirmation_test.dart`: confirmación de los tres métodos operativos,
  exclusión de datos de otros métodos, cliente compartido, bloqueo de salida,
  comprobante posterior al guardado y retorno a Caja.
- `credit_payment_test.dart` y `transfer_payment_screen_test.dart`: reglas de
  cliente obligatorio, confirmación de crédito, límite de referencia y errores.
- `caja_screen_test.dart`: entrada por botón, pestañas y borrador al cancelar.
- `physical_barcode_reader_test.dart`: entrada por Enter, apertura con tecla
  sostenida, cola, foco, lectores y navegación. Sus 108 pruebas pasan.

`dart analyze` termina sin observaciones. Las tres suites de contenido,
coordinación y comprobante reúnen 18 pruebas aprobadas, incluida la prueba
adicional de importe fuera de rango ejecutada por separado.

La última ejecución global de `flutter test` termina con 3036 pruebas aprobadas,
27 omitidas y los tres fallos preexistentes descritos abajo. No quedaron
fallos introducidos por el cambio de cobro. Las omisiones corresponden a
condiciones de entorno o plataformas indicadas por las propias suites.

## Fallos preexistentes comprobados

Se ejecutaron los casos afectados también en una copia limpia de
`9710ed764d8a560ab6c84eeaab89d5d598230d73`, con las mismas dependencias,
reproduciendo los mismos errores:

- `caja_screen_test.dart`, «caja muestra líneas, cantidades e importes y deja
  acciones pendientes deshabilitadas»: espera dos textos exactamente iguales
  a `$109.00`; solo encuentra uno.
- `weighing/sale_barcode_weighing_test.dart`, «search weighs and accumulates
  in persisted draft», tanto `grams=false` como `grams=true`: el segundo
  `tap(find.byType(Card))` encuentra cinco tarjetas y resulta ambiguo.

Estos casos se conservan sin corregir por quedar fuera del cambio de cobro.
Las pruebas automatizadas no sustituyen una prueba con lector físico y teclado
real ni amplían la compatibilidad física documentada para básculas.
