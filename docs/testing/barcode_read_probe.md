# Lector mínimo de escaneo en Caja (sesión 1)

La consulta y la compuerta están implementadas, pero el rearmado temporal sigue
pendiente de validación física. En la revisión 2 del plan, el usuario retiró
esa validación como requisito previo a integrar Caja; los casos físicos quedan
para la verificación final. La sesión 2 debe basarse en el lector existente del
editor de variantes y reutilizar la consulta/compuerta disponibles.
Este prototipo no abre la base de uso, no inicia
sincronización y no habilita los botones de Caja. El lector del editor conserva
su contrato `String?`.

## Ejecutar en Android físico

Desde la raíz de Flutter, usar el ID de un dispositivo que aparezca en
`flutter devices`. A y B deben ser dos etiquetas numéricas distintas; sustituir
los valores por los códigos exactos de esas etiquetas:

```sh
flutter run -d DEVICE_ID -t tool/barcode_read_probe.dart \
  --dart-define=PROBE_CODE_A=012345678905 \
  --dart-define=PROBE_CODE_B=7501031311309
```

La entrada crea dos artículos por pieza y una venta de prueba en SQLite en
memoria. Cada lectura admitida busca localmente y ejecuta el comando real de
borrador. La pantalla muestra las cantidades confirmadas por la proyección y
la consola registra cada incorporación. Cerrar/reabrir el lector conserva la
compuerta y el borrador durante ese proceso. Reiniciar el prototipo descarta
todos sus datos. Usar esta entrada, sin iniciar `lib/main.dart`, para evitar
abrir o recrear una base existente.

Un código desconocido no escribe; si A y B se configuran con el mismo código,
la consulta devuelve dos candidatos y el prototipo no elige ninguno. Selección,
venta medida, tarjetas y accesos definitivos pertenecen a la sesión 2.

## Estrategia experimental

- `mobile_scanner` 7.4.2, `DetectionSpeed.normal`, `detectionTimeoutMs: 200`.
- `scanWindow` nativo coincide con el marco horizontal visible. Se solicitan
  formatos de barras, excluyendo QR; `CodigoBarras` limita la entrada a 32 dígitos.
- Una presentación se consume antes de consultar/guardar, incluso si termina
  con error, desconocido o cancelación. La operación completa es serializada.
- Las observaciones siguen actualizando presencia durante un guardado. Un
  código único distinto delimita otra presentación, permitiendo A → B → A.
- Para el mismo código, una nueva observación tras al menos 1 segundo sin
  observaciones positivas, con cámara activa, rearma la compuerta. No hay un
  temporizador que agregue unidades por sí solo ni dependencia de frames vacíos.
- Diálogos, rutas que cubren el lector, segundo plano y errores suspenden la
  cámara. Al reanudar se conserva la presentación consumida y el primer callback
  establece una nueva base temporal; el tiempo suspendido no acredita retirada.
- Varios códigos distintos en un frame no incorporan nada; se pide enfocar uno.
  No se encolan presentaciones observadas mientras otra operación está ocupada:
  necesitan seguir visibles en un callback nuevo cuando queda libre.
- Cerrar espera cualquier guardado iniciado; no promete rollback. Los callbacks
  de una pantalla cerrada se descartan y la cámara se libera incluso con permiso
  pendiente.

**Límite:** un intervalo de desenfoque de 1 segundo también puede rearmar el mismo
código. El plugin no demuestra retirada física. Este umbral es de calibración,
no una regla definitiva de Caja. La documentación oficial del modo está en
[DetectionSpeed de 7.4.2](https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.2/lib/src/enums/detection_speed.dart).

## Verificación física pendiente para la sesión 3

Estos casos no bloquean la pantalla ni la conexión de los botones en sesión 2.

Anotar modelo, Android, formato y valor textual detectado, duración y cantidades
antes/después de cada caso. Repetir con EAN-13, EAN-8 y UPC-A disponibles, sin
quitar ni agregar ceros para resolver diferencias del detector.

1. Mantener A inmóvil durante 20 segundos: A suma exactamente una pieza.
2. Introducir pequeñas variaciones de luz y enfoque: no suma piezas extra.
3. Tres presentaciones de A, retirando la etiqueta más de 1 segundo entre ellas:
   A suma tres piezas. No pausar la cámara para simular retirada.
4. A → B → A: A suma dos y B una, incluso con transiciones rápidas.
5. Dos códigos dentro del marco: cero incorporaciones hasta enfocar uno.
6. Pasar a segundo plano o cubrir/cerrar/reabrir el lector dejando A enfrente:
   no suma otra pieza por reanudar.

Si el criterio temporal agrega piezas extra o impide relecturas intencionales,
corregir el fallo observado y evaluar, si hace falta, una adaptación versionada
del detector que exponga
presencia/ausencia dentro del área y tenga pruebas nativas. No editar `.pub-cache`
ni sustituir el comportamiento por repetición temporizada o botón manual.
No exigir esa adaptación como condición especulativa para iniciar sesión 2.

## Verificación independiente

```sh
dart run build_runner build
dart analyze
flutter test test/data/repositories/producto_codigo_barras_test.dart \
  test/presentation/pages/caja/barcode
flutter test
flutter build apk --debug -t tool/barcode_read_probe.dart
```

Los tests usan SQLite desechable, reloj controlado y la plataforma falsa de cámara.
Prueban la lógica, el ciclo de vida y eventos/refs en ambos modos; no sustituyen
retirada, foco, formatos ni permisos físicos del dispositivo.
