import '../../../../application/edicion_masiva/base_revision_masiva.dart';
import '../../../../application/edicion_masiva/cambio_explicito.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';

/// Texto sin perder errores ni distinguir vacío de un campo aún sin tocar.
class FilaEdicionForm {
  const FilaEdicionForm({
    required this.original,
    required this.baseProducto,
    this.venta,
    this.costo,
    this.cantidad,
    this.proveedorCapturado = false,
    this.proveedorId,
    this.fechaInformada,
  });

  final FilaCatalogoMasivo original;
  final BaseRevisionMasiva baseProducto;
  final String? venta;
  final String? costo;
  final String? cantidad;
  final bool proveedorCapturado;
  final String? proveedorId;
  final DateTime? fechaInformada;

  FilaEdicionForm copiar({
    CambioExplicito<String?> venta = const CambioExplicito.conservar(),
    CambioExplicito<String?> costo = const CambioExplicito.conservar(),
    CambioExplicito<String?> cantidad = const CambioExplicito.conservar(),
    bool? proveedorCapturado,
    CambioExplicito<String?> proveedorId = const CambioExplicito.conservar(),
    DateTime? fechaInformada,
  }) => FilaEdicionForm(
    original: original,
    baseProducto: baseProducto,
    venta: venta.establecer ? venta.valor : this.venta,
    costo: costo.establecer ? costo.valor : this.costo,
    cantidad: cantidad.establecer ? cantidad.valor : this.cantidad,
    proveedorCapturado: proveedorCapturado ?? this.proveedorCapturado,
    proveedorId: proveedorId.establecer ? proveedorId.valor : this.proveedorId,
    fechaInformada: fechaInformada ?? this.fechaInformada,
  );
}
