class ResolvedEventBase {
  const ResolvedEventBase({
    this.serverSequence,
    this.waitsForLocalDependency = false,
  });

  final int? serverSequence;
  final bool waitsForLocalDependency;
}
