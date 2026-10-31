/// La revisión presentada para cobrar dejó de ser la persistida.
class SaleDraftChangedException extends StateError {
  SaleDraftChangedException()
    : super('El borrador cambió o ya fue cobrado. Revísalo antes de cobrar.');
}
