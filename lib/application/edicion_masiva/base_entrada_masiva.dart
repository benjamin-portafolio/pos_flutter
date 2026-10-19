import '../../domain/inventario/unidad_inventario.dart';
import 'base_revision_masiva.dart';

/// Vínculo directo, unidad y revisión independiente del saldo materializado.
class BaseEntradaMasiva {
  const BaseEntradaMasiva({
    required this.recurso,
    required this.unidad,
    required this.saldoVersion,
    required this.saldoEventId,
    required this.saldoServerSequence,
    required this.existenciaAtomic,
    required this.disponibleAtomic,
  });

  final BaseRevisionMasiva recurso;
  final UnidadInventario unidad;
  final int saldoVersion;
  final String saldoEventId;
  final int? saldoServerSequence;
  final int existenciaAtomic;
  final int disponibleAtomic;

  bool mismoEstado(BaseEntradaMasiva other) =>
      recurso.mismoEstado(other.recurso) &&
      unidad.id == other.unidad.id &&
      unidad.code == other.unidad.code &&
      unidad.dimension == other.unidad.dimension &&
      unidad.factorAtomico == other.unidad.factorAtomico &&
      unidad.maximosDecimales == other.unidad.maximosDecimales &&
      unidad.activa == other.unidad.activa &&
      saldoVersion == other.saldoVersion &&
      saldoEventId == other.saldoEventId &&
      existenciaAtomic == other.existenciaAtomic &&
      disponibleAtomic == other.disponibleAtomic;
}
