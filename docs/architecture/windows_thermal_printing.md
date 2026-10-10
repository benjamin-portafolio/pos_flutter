# Impresión térmica en Windows

La configuración es local (`printer_settings.json`), independiente de Drift,
ventas y sincronización. `PrinterProfile.transport` distingue Bluetooth Android
de la cola Windows. Windows conserva exactamente el nombre instalado; su clave
local es `windows:<nombre>`. La versión 2 del archivo guarda el transporte.
La versión 1 se interpreta explícitamente como Bluetooth y conserva su
predeterminada al cargar y al guardar en el nuevo formato.

`PrinterGateway.listDestinations` enumera destinos solo a petición del usuario.
La fábrica en DI selecciona Android Bluetooth o Windows; construirla no consulta
impresoras ni crea trabajos. `TicketPrintService` y el generador ESC/POS siguen
siendo compartidos por venta, cotización, reimpresión y prueba.

El adaptador Windows usa FFI sobre `winspool.drv`: `EnumPrintersW` (colas locales),
`OpenPrinterW`, `StartDocPrinterW` con datatype `RAW`, `WritePrinter`,
`EndDocPrinter` y `ClosePrinter`. Cada operación bloqueante se ejecuta en un
isolate trabajador. Las bandas pertenecen a un único documento. Un fallo de
escritura parcial no reenvía bytes; los trabajos incompletos se abortan con
`AbortPrinter`. La finalización ambigua no se repite. Si falla el cierre, el
servicio conserva su bloqueo de seguridad. Los timeouts informan al usuario,
pero mantienen la exclusión hasta que termina la operación original y su
limpieza. La aceptación de Windows no confirma salida física del papel.

Referencias de API:
- [EnumPrinters](https://learn.microsoft.com/windows/win32/printdocs/enumprinters)
- [StartDocPrinter](https://learn.microsoft.com/windows/win32/printdocs/startdocprinter)
- [Envío RAW](https://learn.microsoft.com/windows/win32/printdocs/sending-data-directly-to-a-printer)

## Prueba manual de la POS-58

1. Confirma en Windows la cola `POS-58`, controlador `POS-58 11.3.0.1` y puerto
   `USB001`. La app usa el nombre de la cola; el controlador administra el puerto.
2. Abre Configuración → Impresoras → Agregar impresora. Selecciona `POS-58` en
   Impresoras instaladas. No selecciones destinos PDF ni impresoras de oficina.
3. Guarda con papel de 58 mm, ancho inicial de 384 puntos, imagen `gsV0` y corte
   desactivado. Son valores iniciales del perfil, no una garantía de compatibilidad.
4. Pulsa Imprimir prueba tú mismo. Revisa el papel y la cola de Windows.
5. En Editar, ajusta el ancho en múltiplos de 8 y prueba `escStar`, `gsV0` o `gsL`
   según los resultados. Activa corte solo si verificas que el equipo lo admite.
6. Selecciona Elegir predeterminada. Desde un ticket de venta, cotización o
   reimpresión, pulsa Imprimir y confirma el destino.
7. Ante timeout o envío ambiguo, revisa papel y cola antes de una repetición
   manual. La app no reintenta automáticamente.

Durante el desarrollo no se crearon trabajos físicos. La verificación nativa
fue únicamente enumeración, que devolvió `POS-58` y `Microsoft Print to PDF`.
Los tests Windows inyectan un transporte simulado.
