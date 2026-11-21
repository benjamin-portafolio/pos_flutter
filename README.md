# pos_flutter

A new Flutter project.

En Gestión del inventario → Artículos, el lector sobre `+` permite escanear y
editar una coincidencia o asignar/reemplazar el código de una variante existente
con confirmación. [Verificación y pruebas físicas pendientes](docs/testing/inventory_barcode_verification.md).

## Recuperación por HTTP en red local

HTTPS es el valor predeterminado. Para una instalación que permita recuperar y
vincular por HTTP en una red local de confianza, compilar con:

```sh
flutter build apk --release --dart-define=POS_ALLOW_LOCAL_HTTP=true
```

Esta opción admite IP privadas IPv4 literales (10/8, 172.16/12 y 192.168/16),
por ejemplo `http://192.168.0.202:3000`. No admite HTTP hacia dominios ni IP
públicas. La pantalla informa que la conexión no está cifrada. Se aplica la
misma política a comprobación, transferencia y bootstrap/vinculación. No cambia
las reglas de standalone ni requiere cambios de base de datos.
