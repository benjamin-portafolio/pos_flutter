import '../../edicion_masiva/base_entrada_masiva.dart';

/// Entrada revisada: nunca sustituye la base del recurso ni del saldo por la viva.
class RegistrarEntradaConfirmadaCommand {
  const RegistrarEntradaConfirmadaCommand({
    required this.base,
    required this.cantidadAtomic,
  });

  final BaseEntradaMasiva base;
  final int cantidadAtomic;
}
