# Eliminación de recursos de inventario

El editor de nombre/existencias ofrece **ELIMINAR RECURSO** al final, únicamente
para recursos existentes. Confirmar ejecuta la baja independientemente del
formulario; el diálogo advierte si hay nombre o movimiento sin guardar.
Cancelar no guarda cambios ni elimina. Un fallo conserva el formulario y permite
reintentar, mostrando el motivo cuando existe un bloqueo de negocio.

## Contrato y conservación

`recurso_inventario_eliminado`, agregado `inventory_item`, transporta únicamente
`{base_event_id}`; el sobre declara `base_version` y la secuencia oficial conocida.
Se marca `active = false` y avanza versión/evento sin borrar identidad, balance,
movimientos, memoria de variantes ni ventas. Los listados existentes omiten
inactivos. Un replay del alta no reactiva el recurso; un eco solo avanza secuencia.

No reutiliza `recurso_inventario_descartado`: ese evento sigue limitado al descarte
físico automático de un autogenerado elegible en standalone.

## Bloqueos

La intención se prepara y aplica dentro de una transacción SQLite. El comando y
el handler local verifican saldo materializado, existencias y disponible iguales
a cero, ausencia de vínculos directos y recetas (incluidas variantes inactivas),
y ausencia de borradores u operaciones sin aplicar que necesitan el recurso.
El historial de movimientos y las ventas confirmadas no bloquean por sí solos:
las filas se conservan para auditoría y ajustes históricos.

NestJS valida contrato y base, bloquea el recurso y balance en PostgreSQL y vuelve
a comprobar saldo y dependencias. Los nuevos vínculos y movimientos requieren un
recurso activo. Las ventas históricas siguen usando las identidades conservadas.
La baja oficial recibida por pull no queda vetada por borradores locales.

## Modos y concurrencia

Ambos modos declaran `LocalEventRef.affects(inventory_item)`. Standalone conserva
`delivery_status = not_required`, sin filas en event_refs ni actividad de red.
Server_sync persiste refs y deja el evento pendiente. Push espera a la creación o
edición base; aceptación/eco distribuye la baja por el transporte existente.
Rechazo o conflicto restaura la baja optimista. Una mutación oficial del recurso
restaura primero la cadena local en orden inverso. Un artículo oficial que vincula
el recurso restaura primero una baja pendiente y la marca en conflicto. Si llega
después la aceptación oficial de una baja restaurada, el receptor la aplica de
nuevo en vez de tratarla como un eco de metadatos.
La revalidación comprueba también nuevas dependencias o saldo cambiado por ventas.

No hay cambios de esquema ni migraciones. Hay que actualizar servidor y clientes
antes de utilizar esta función entre dispositivos: un cliente anterior no conoce
el nuevo evento. Un servidor anterior puede rechazarlo; el cliente restaura la baja.

## Verificación

- `test/data/local/drift/inventory_deletion_test.dart`: ambos modos, conservación,
  bloqueos, refs, replay, revalidación, push y restauración ante rechazo/conflicto.
- `test/presentation/pages/gestion_inventario/recursos/inventory_resource_form_screen_test.dart`:
  confirmación, cancelación, cambios pendientes y motivo de bloqueo.
- NestJS: contrato y `src/sync/inventory-event.handler.postgres.spec.ts`, ejecutado
  con PostgreSQL real en un esquema temporal aislado, incluye push/duplicado/pull.
