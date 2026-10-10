# Transporte Bluetooth del POS

Dependencia local única `pos_bluetooth_printer` **0.1.0**, fijada en el pubspec
principal y su lockfile. Android API 24+, Flutter 3.41.6/Dart 3.11.4,
AGP 8.11.1/Kotlin 2.2.20/Gradle 8.14. No registra código en macOS/iOS.

Se inspeccionaron los archivos publicados exactos de
[print_bluetooth_thermal 1.2.1](https://pub.dev/api/archives/print_bluetooth_thermal-1.2.1.tar.gz)
y [flutter_bluetooth_printer 2.24.0](https://pub.dev/api/archives/flutter_bluetooth_printer-2.24.0.tar.gz).
El primero abandona llamadas sin responder cuando falta CONNECT, escribe en el
hilo principal y conserva solamente el OutputStream, sin una barrera de cierre
del socket. El segundo usa descubrimiento (SCAN/ubicación en Android antiguo)
y el mismo monitor para escribir/cerrar, impidiendo abortar una escritura
bloqueada con ese cierre. Se aplica la alternativa del plan: puente Android
mínimo propio, sin instalar esos paquetes ni alterar `.pub-cache`.

## Contrato y uso

Application depende exclusivamente de `PrinterGateway`. El adaptador de data
traduce el canal `pos/bluetooth_printer` y sus errores. Todos los envíos deben
usar **la instancia compartida de `TicketPrintService` de GetIt**: `printTest`
(`printTest` usa el documento de calibración y el encoder térmico) o
`printTicket` (documento/perfil capturados), además de `send` para bytes.
No construir servicios por pantalla
ni enviar directamente desde UI al canal/gateway.

La fase 2 puede consultar `availability`, `permissionStatus`, solicitar
`requestPermission` por acción explícita y listar `bondedDevices`. El usuario
elige la dirección devuelta por Android; `PrinterProfile` captura alias, papel,
ancho y método de imagen. `PrinterSettings` valida direcciones únicas y una
predeterminada presente. Este paquete no descubre, vincula ni clasifica los
dispositivos como impresoras compatibles. No necesita internet ni conocer el
modo del POS.

Canal nativo:

| Método | Argumento / respuesta |
|---|---|
| availability | `ready`, `off`, `no_hardware`, `permission_required` |
| permissionStatus / requestPermission | `granted`, `denied`, `permanently_denied` |
| bondedDevices | Lista de `{address, name}` |
| connect | Dirección vinculada; completa después de `BluetoothSocket.connect` |
| write | `Uint8List`; completa después de todas las escrituras y `flush` |
| close | Completa después de cierre **y terminación** del trabajo nativo previo |

SPP/RFCOMM seguro, UUID estándar `00001101-0000-1000-8000-00805f9b34fb`.
Un socket por adaptador, reemplazo explícito del destino, sin fallback a otros
transportes. Escritura en worker, bloques de transporte de 256 bytes con pausa
de 40 ms después de cada bloque, incluido el último de cada write. La siguiente
banda no empieza hasta terminar esa pausa y el flush. Este ajuste conservador
responde a la foto del 2026-10-09: prueba raster legible pero recibos/cotizaciones
con tramos binarios interpretados como texto. La causa física y el resultado
del ajuste siguen pendientes de nueva impresión; no hay detección automática
de buffer ni acuse de papel. No se agregan bytes, inicializaciones, avances, corte ni cajón en el
transporte. La prueba de configuración usa el mismo renderer por bandas que
ventas/cotizaciones y el método del perfil, con ñ/tildes, nombre largo, medida,
importe, reglas de margen y pie. El raster no certifica el ancho físico.

## Permisos y finalización

El manifest de la app declara `BLUETOOTH` con `maxSdkVersion=30` y
`BLUETOOTH_CONNECT`. No llama a `startDiscovery` ni `cancelDiscovery`, por lo que
no necesita SCAN, ADMIN, ubicación ni anunciar dispositivos. Bluetooth es una
característica opcional. Se revisa permiso antes de acceder a los vinculados,
conectar y escribir cada banda; las excepciones de revocación producen un error.
No se consultan dispositivos, solicitan permisos o abren sockets al registrar
el plugin/crear DI.

Límites nativos: permiso 30 s, conexión 10 s, escritura 20 s. La solicitud de
permiso marca vencido su plazo sin completar el canal: conserva el futuro
pendiente hasta respuesta/cierre de Activity/engine y rechaza una segunda
solicitud. Después informa timeout sin continuar al envío. El deadline de
application puede avisar a los 35 s y drena ese futuro, manteniendo exclusión.
El plazo de I/O inicia un cierre del socket desde otro executor. Android
[documenta que `BluetoothSocket.close` aborta operaciones pendientes](https://developer.android.com/reference/android/bluetooth/BluetoothSocket).
La barrera espera **también** al worker y al ejecutor que cerró; no presume que
el retorno de `close` por sí solo finaliza los callbacks pendientes.

Límites de application: permiso/listado 35 s, conexión 15 s, escritura 30 s,
cierre 10 s. Un `Future.timeout` informa al llamador, pero el servicio sigue
ocupado hasta drenar el future original y cerrar. Una conexión tardía tras timeout
no llega a escribir. Un cierre tardío exitoso libera; un cierre fallido pone el
servicio/transporte en cuarentena. `dispose` deja de aceptar trabajos y espera
cierre real. `restartDependencyInjection` espera ese `dispose` antes del reset;
si falla, conserva las dependencias anteriores. No hay reintentos de impresión,
cola, historial persistente, servicios de impresión en segundo plano ni envíos
al volver de otra ruta o reiniciar.

Si un driver queda bloqueado incluso después de cerrar el socket, la app puede
reportar timeout pero **sigue ocupada** y el reemplazo de DI espera. No se acepta
otro envío sobre trabajo posiblemente activo. Un error después de iniciar
`write` tiene `mayHavePrinted=true`; ni un retorno exitoso ni `flush` confirman
salida física, papel o tapa.

## Verificación

```sh
dart analyze
flutter test
flutter build apk --debug
cd android
./gradlew :pos_bluetooth_printer:testDebugUnitTest
```

Las pruebas Dart comprueban errores, permisos, snapshot, concurrencia, timeout
con future pendiente, cierre y reinicio de DI. Las JVM ejercitan el transporte
con sockets controlados: cancelación real de su worker, cierre bloqueado,
socket tardío, flush, bandas y cambio de destino. Ninguna certifica el stack
Bluetooth de un Android real. Faltan Android/impresora para comprobar SPP,
permisos reales, pérdida de conexión, tiempos y resultado en papel.
