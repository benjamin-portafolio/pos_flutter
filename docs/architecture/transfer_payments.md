# Transferencias y reportes de cobros

Implementado 2026-09-23. Especificación completa en el proyecto de análisis:
`03 - Dominio/Modulos/Pagos por transferencia y reportes por metodo.md`.

- Caja → Transferencia bancaria → total y referencia opcional → confirmar → recibo.
- `ConfirmarVentaCommand.paymentReference` se normaliza antes de serializar
  `VentaConfirmadaPayload.payment_reference`. Máximo 500 caracteres; vacío es null.
- `transfer` exige payment_id, recibido igual al total y cambio cero. Conserva
  cliente opcional, MXN, un pago directo por venta y transacción/evento existentes.
- `CollectionRepositoryImpl` combina pagos directos y abonos sin unirse a
  `credit_allocations`. La fecha directa viene del evento de confirmación; los
  abonos usan occurred_at_ms. No se filtra por estado de entrega.
- Informes muestra subtotales y movimientos con referencia, origen, venta/cliente,
  fecha, usuario, dispositivo y entrega. El recibo PNG muestra método y referencia.
- Standalone conserva not_required y omite refs persistidas; sync continúa con
  contratos tipados, refs, preflight, push, pull y reconocimiento de ecos existentes.

## Esquema y operación

Regenerar con `dart run build_runner build`. schemaVersion permanece en 7;
`_resetDatabaseOnStartup` recrea bases antiguas sin method/reference. Esto pierde
los datos locales por la política de desarrollo vigente. Los respaldos antiguos
marcados como restaurados se rechazan. Bases de uso requieren una estrategia de
preservación acordada antes de actualizar. No se abrió ninguna base de uso.

Actualizar servidor con `1790208000000-AddTransferSales` y todas las tablets que
reciben eventos antes del uso. No hay pagos mixtos, validación bancaria posterior
ni conversión automática de historial standalone en eventos pendientes.

## Verificación ejecutada

Drift regenerado; dart analyze sin incidencias; flutter test: 518 pruebas
aprobadas. Backend: build y ESLint correctos, 31 suites / 231 pruebas con
PostgreSQL temporal aislado. No se probaron tablets físicas ni se desplegó.
