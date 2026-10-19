import '../../../../application/edicion_masiva/cambio_variante_masiva.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import 'fila_edicion_form.dart';

enum CampoEdicionMasiva { venta, costo, proveedor, fecha, cantidad, base }

enum EstadoFilaMasiva { sinCambios, cambios, error }

class FilaRevisionMasiva {
  FilaRevisionMasiva({
    required this.captura,
    required this.actual,
    required this.cambio,
    required Map<CampoEdicionMasiva, String> errores,
  }) : errores = Map.unmodifiable(errores);

  final FilaEdicionForm captura;

  /// Foto nueva para explicar bases obsoletas sin reemplazar lo capturado.
  final FilaCatalogoMasivo? actual;
  final CambioVarianteMasiva? cambio;
  final Map<CampoEdicionMasiva, String> errores;

  EstadoFilaMasiva get estado => errores.isNotEmpty
      ? EstadoFilaMasiva.error
      : cambio!.tieneCambios
      ? EstadoFilaMasiva.cambios
      : EstadoFilaMasiva.sinCambios;
}
