# Flujo rápido de venta en Caja

## Funciones y controles actuales

| Acción | Tecla o control |
| --- | --- |
| Editar la cantidad de la última línea | F2 |
| Editar una línea específica | Lápiz de la línea |
| Confirmar cantidad y regresar al lector | Enter o Listo |
| Descartar cantidad escrita | Escape o Cancelar edición |
| Seleccionar una línea | Clic en su nombre |
| Eliminar la línea seleccionada directamente | Supr |
| Eliminar una línea directamente | Papelera |
| Ajustar piezas sin abrir el editor | Botones + / − de la línea |
| Volver de resultados de búsqueda a Caja | Escape |
| Recuperar lector después de editar o volver a Caja/app | Automático |

- Eliminar ya no solicita confirmación, tanto en la línea como en el editor.
  Disminuir con − hasta cero también elimina directamente. No hay Deshacer.
- F2 edita la última línea de la lista; no busca por fecha de último escaneo.
- La captura manual de cantidad es temporal. Enter/Listo espera el resultado del
  comando antes de cerrar. Los ajustes + / − guardan inmediatamente: cancelar
  la captura manual no deshace esos ajustes.
- Peso y volumen conservan captura decimal y el paso de referencia del editor.
- Escape desde búsqueda utiliza la misma barrera del botón Atrás: espera las
  lecturas aceptadas antes de salir. No abandona comandos en curso.
- Si hay un diálogo sobre la búsqueda, Escape cierra primero ese diálogo.
- El lector conserva su campo y sesión durante ajustes directos cuando está
  libre. Si hay lecturas pendientes, errores o una edición abierta se mantiene
  la barrera normal de finalización.
- Durante ajustes locales no se inserta Reanudar lector ni desaparece el campo,
  evitando el salto de altura. Cantidades y totales muestran datos persistidos.
- Los errores del lector siguen requiriendo reanudación explícita: recuperar
  foco no reconoce el fallo ni reintenta la intención fallida.
- Tab conserva la transferencia voluntaria de foco.

## Verificación

Pruebas en `draft_item_inline_editor_test.dart`, `caja_screen_test.dart`,
`physical_barcode_reader_test.dart` y `unified_search_test.dart` cubren eliminación
sin confirmación, disminución hasta cero, recuperación del foco, continuidad del
escaneo, estabilidad del campo y Escape con resultados, diálogos y lecturas en
curso. Se usan una base SQLite aislada y teclado simulado.

La suite global de Windows presenta fallos fuera de este cambio, entre ellos
fixtures en rutas absolutas de macOS y directorios temporales bloqueados.
No se cambian esquema, eventos, comandos ni sincronización.

Falta comprobar con el lector HID real: escanear, F2, cantidad, Enter, siguiente
código; cancelar con Escape; ajustar con + / −; eliminar con papelera/Supr;
buscar y volver con Escape; cambiar de ventana con y sin formulario abierto.
Las pruebas automatizadas no acreditan compatibilidad física ni latencia real.

Resultado de esta revisión (2026-11-19): `dart analyze` sin observaciones;
22/22 pruebas de editor y Caja y 24/24 de navegación, eliminación y lector.
`flutter test --fail-fast` se interrumpió después de fallar por el fixture
`open-valid.json` ausente en la ruta absoluta de macOS de `cash_flow_test.dart`.
