import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';

/// Dependencia de comandos para pruebas del contenedor sin cambios de venta.
/// Falla ante cualquier escritura inesperada.
class FakeVentaBorradorCommandService implements VentaBorradorCommandService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
