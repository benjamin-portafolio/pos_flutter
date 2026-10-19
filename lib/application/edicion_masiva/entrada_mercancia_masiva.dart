import '../../domain/articulos/precio_venta.dart';
import 'base_entrada_masiva.dart';

class EntradaMercanciaMasiva {
  EntradaMercanciaMasiva({required this.base, required this.cantidadAtomic}) {
    if (cantidadAtomic <= 0 || cantidadAtomic > PrecioVenta.maxUnidadMenor) {
      throw const FormatException('La entrada debe ser positiva y segura.');
    }
  }

  final BaseEntradaMasiva base;
  final int cantidadAtomic;
  int get existenciaPrevistaAtomic => base.existenciaAtomic + cantidadAtomic;
}
