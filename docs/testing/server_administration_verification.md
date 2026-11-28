# Administración del servidor: verificación 2026-11-27

Implementación: menú lateral de escritorio (`server_sync`) → Administración del
servidor → Panel de administración → Recuperación del servidor. Cliente HTTP por fábrica en composición; la UI
solo depende de la interfaz de aplicación. No hay cambios de esquema ni de los
comandos/eventos de negocio.

## Comprobaciones

- `dart analyze`: sin incidencias.
- Regresión de recuperación, shell, menú y límites entre capas: **102 pruebas aprobadas**.

  ```sh
  flutter test test/architecture/import_boundaries_test.dart test/widget_test.dart test/data/local/recovery test/presentation/pages/recovery test/presentation/pages/pantalla_principal/menu_lateral_test.dart
  ```

- Se verificó acceso Windows/macOS/Linux y exclusión móvil/standalone, navegación,
  ausencia de llamadas al abrir, confirmación/cancelación, aprobación de la solicitud
  elegida, invalidación al editar destino y respuesta perdida después de mutación.
- Cliente: sin red en standalone, política de transporte existente, health sin
  secreto, identidad/generación comprobadas, revisión esperada y sin reintentos de
  escritura ni seguimiento de redirecciones.
- NestJS: build aprobado; ESLint de los cuatro archivos nuevos sin incidencias;
  suite general **632 aprobadas, 401 omitidas** (incluye 10 nuevas pruebas HTTP).
  Las pruebas HTTP usan Nest real con adaptador DB simulado; las suites optativas
  PostgreSQL no se habilitaron. No se ejecutó recuperación sobre datos de negocio.

## Suite global Flutter

La ejecución completa inicial terminó con 3618 aprobadas, 41 omitidas y dos fallos:

1. Límite presentation → data de la pantalla nueva: corregido con inyección por
   fábrica; la regresión posterior de 102 pruebas incluye la comprobación aprobada.
2. `physical_barcode_assignment_test.dart`, «segundo plano conserva asignación y
   exige reanudar antes de agregar», línea 756: espera 1 línea de venta y recibe 2.
   Reproduce aislado tanto con el cambio como al restaurar temporalmente desde HEAD
   los dos archivos productivos preexistentes modificados por esta tarea
   (`data_dependencies.dart` y `menu_lateral.dart`). Se restauraron después los cambios
   de la tarea. Ese comportamiento previo de Caja no se modificó.

No se presenta la suite global como verde. No se repitió toda la suite después del
ajuste de composición; sí el conjunto de regresión indicado sobre el código final.
No se acredita TLS real, despliegue productivo ni una recuperación entre equipos con
esta pantalla. El ensayo de recuperación anterior conserva sus propios alcances.

## Configuración y operación

Ver `pos-nest/docs/recovery-administration.md`: instalar en NestJS el SHA-256 de una
credencial administrativa aleatoria independiente y usar el secreto original en
la pantalla. Sin configuración, la API responde 503. El destino debe tener esquema
compatible y estar vacío; la pantalla no instala migraciones ni reemplaza datasets.

## Actualización: contraseña elegida por consola

La configuración nueva se realiza con `npm run admin:password` después de compilar
NestJS. Se pide dos veces una contraseña de 15–128 caracteres sin mostrarla; se
guarda Argon2id con sal en `POS_RECOVERY_ADMIN_PASSWORD_HASH`. El asistente conserva
las otras variables, elimina las asignaciones administrativas antiguas/duplicadas
y sustituye el `.env` mediante archivo temporal privado y rename. No cambia DB ni
reinicia el servidor automáticamente. La configuración anterior SHA-256 solo se
usa cuando la variable nueva no existe; nunca es una alternativa si Argon2 falla.

Flutter acepta contraseñas Unicode y conserva espacios iniciales/finales. Envía
Basic UTF-8 con usuario fijo `admin`; las credenciales hexadecimales de 64 caracteres
conservan Bearer para compatibilidad con el servidor anterior. No cambia los tokens
de recuperación de dispositivos ni la prohibición de red en standalone.

Comprobaciones adicionales:

- Backend final: build y ESLint aprobados; suite general **644 aprobadas, 401
  omitidas**. Incluye hash con sal/contraseña incorrecta, precedencia sin fallback,
  Unicode, controles/longitud, preservación dotenv (incluye multilinea/CRLF),
  reemplazo de variables anteriores, permisos, bloqueo y rechazo de symlinks.
- Ensayo del asistente compilado en terminal PTY: aprobado en macOS con `.env`
  temporal. Comprueba entrada oculta, confirmación fallida seguida de correcta,
  lectura dotenv, verificación Argon2, Unicode/espacios y Ctrl+C sin cambios.
  Reproducible desde NestJS: `python3 test/support/recovery-admin-password-pty.py`.
- Se mantuvo intacto el `.env` real y no se eligió una contraseña por el usuario.
- El análisis Dart del código final no reportó incidencias.
- Suite completa Flutter sobre el código final: **3622 aprobadas, 41 omitidas y
  1 fallo previo** en `physical_barcode_assignment_test.dart`, caso de segundo
  plano, línea 756 (espera una línea y obtiene dos). Es el mismo fallo aislado y
  acreditado sin los cambios de administración en la comprobación anterior.
  Los casos de contraseña, pantalla y compatibilidad pasaron; no se declara verde
  la suite global. Análisis Dart sin incidencias.

## Corrección de entrada de contraseña en escritorio

Se investigó un formulario que mostraba foco pero no admitía escritura. El debug
macOS registró errores repetidos de `HardwareKeyboard` por `KeyDownEvent` duplicado.
No se cambió el SDK ni se introdujo un reinicio global del estado de teclas.

El formulario ahora mantiene FocusNode y keys propios para URL y contraseña y
conserva controles habilitados, de solo lectura durante peticiones, evitando
reemplazarlos por controles deshabilitados y volver a habilitarlos. La contraseña
usa el tipo de entrada de contraseña explícito, dispone de mostrar/ocultar sin
perder el contenido, y Enter permite pasar de URL a contraseña y consultar estado.
Se conserva el secreto exacto, la invalidación de consultas y su descarte al salir.

Verificación:

- Build debug macOS aprobado y aplicación reabierta conservando la instalación.
- El usuario confirmó expresamente que ya podía escribir en la app reabierta.
  No se utilizó ni transmitió su contraseña durante el diagnóstico.
- 23 pruebas enfocadas de pantalla y menú aprobadas. El caso nuevo se ejecutó
  para macOS/Windows/Linux: foco/conexión editable, mostrar/ocultar conservando
  texto, consulta por Enter, fallo remoto y edición posterior.
- `dart analyze`: sin incidencias.
- La prueba real acredita la combinación de ajuste del formulario y reinicio de
  la app; no aísla cuál de los dos resolvió por sí solo el estado nativo anterior.
- Suite global tras esta corrección: **3625 aprobadas, 41 omitidas y el mismo fallo
  previo** del lector físico al volver de segundo plano. No aparecen fallos nuevos
  en el formulario, navegación o contraseña. No se modificó ese lector.

## Dashboard de administración

La entrada del menú abre un panel con una tarjeta «Recuperación del servidor»
y acceso «Entrar». El formulario existente vive en `ServerRecoveryScreen`;
volver desde recuperación regresa al panel. El panel no crea el cliente HTTP
ni solicita credenciales o estado del servidor al abrirse. Conserva el acceso
solo en escritorio y modo `server_sync`. No incluye opciones futuras ficticias.

Los tests de recuperación conservan los casos de consulta, contraseña,
confirmación, aprobación e invalidación. El test del menú recorre panel →
recuperación → panel → menú; los del dashboard verifican la entrada sin
formulario y el bloqueo en standalone.

Verificación del dashboard:

- `dart analyze`: sin incidencias.
- Dashboard, recuperación y menú: **25 pruebas aprobadas**.
- Suite completa: **3635 aprobadas, 41 omitidas y 2 fallos**. Se mantiene
  el fallo documentado del lector físico al volver de segundo plano. Además,
  cotizaciones agotó `pumpAndSettle` en «Caja guarda una vez y Nueva captura
  limpia sólo origen; historial conserva documento»; ese caso pasó al repetirlo
  de forma aislada. La suite global no se declara verde.

## Alta de dispositivos desde administración

El panel incluye «Alta de dispositivos», independiente de recuperación, con URL,
contraseña administrativa y consulta de estado. Reutiliza el formulario común
`ServerAdministrationFormScreen`; las pantallas de recuperación y alta conservan
rutas propias. El interruptor pide confirmación, consulta nuevamente tras escribir
y descarta el estado accionable ante errores o edición de URL/contraseña.

El backend amplía el canal administrativo autenticado con `automatic_enrollment`
y acciones `enrollment-enable`/`enrollment-disable`. Bloquea cambios durante una
recuperación y altas antes de publicar un dataset activo; coteja identidad,
generación y revisión con bloqueo transaccional y auditoría. No revoca bindings
existentes ni modifica el esquema, por lo que no requiere migración ni ER nuevo.
En escritorio, un intento completado ofrece «Permitir conectar otros dispositivos»
con la URL del intento; no habilita altas automáticamente. En móvil se conserva
la administración desde computadora. No se fusionan ni reemplazan equipos con datos.

Verificación de este agregado:

- NestJS: build y ESLint aprobados; suite general 646 aprobadas, 401 omitidas.
  HTTP administrativo: 16 aprobadas; incluye altas, estado, concurrencia,
  bloqueos y auditoría con base simulada.
- Flutter: `dart analyze` sin incidencias. Conjunto de administración, menú,
  recuperación y transporte: 44 aprobadas. Después de agregar la comprobación
  del enlace desde recuperación completada: 20 aprobadas en recuperación,
  alta y transporte. Se comprueba el destino heredado y que no se abre red ni
  se habilita alta al navegar.
- No se usó la contraseña del usuario ni se cambió el estado del servidor real.
  El despliegue requiere actualizar/reiniciar NestJS y actualizar Flutter.
- Suite completa Flutter: **3645 aprobadas, 41 omitidas, 1 fallo**. Coincide
  con el fallo previamente documentado en
  `physical_barcode_assignment_test.dart:756`, «segundo plano conserva asignación
  y exige reanudar antes de agregar» (espera una línea y obtiene dos). No se
  modificó ese flujo; no se declara verde la suite global.
