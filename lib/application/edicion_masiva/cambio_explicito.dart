/// Conservar y establecer son intenciones distintas, incluso para cero/null.
class CambioExplicito<T> {
  const CambioExplicito.conservar() : establecer = false, _valor = null;
  const CambioExplicito.establecer(T valor) : establecer = true, _valor = valor;

  final bool establecer;
  final T? _valor;

  T get valor {
    if (!establecer) throw StateError('La intención es conservar el valor.');
    return _valor as T;
  }
}
