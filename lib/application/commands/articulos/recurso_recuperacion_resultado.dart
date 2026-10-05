sealed class RecursoRecuperacionResultado {
  const RecursoRecuperacionResultado();
}

class RecursoNuevoResultado extends RecursoRecuperacionResultado {
  const RecursoNuevoResultado();
}

class RecursoRecuperableResultado extends RecursoRecuperacionResultado {
  const RecursoRecuperableResultado({
    required this.inventoryItemId,
  });

  final String inventoryItemId;
}

class RecursoSeleccionRequeridaResultado extends RecursoRecuperacionResultado {
  const RecursoSeleccionRequeridaResultado({
    required this.motivo,
  });

  final String motivo;
}

class RecursoNoDisponibleResultado extends RecursoRecuperacionResultado {
  const RecursoNoDisponibleResultado({
    required this.motivo,
  });

  final String motivo;
}
