/// An enumerated destination, not proof of a particular scale model.
class ScaleDevice {
  const ScaleDevice({
    required this.port,
    required this.name,
    required this.systemId,
  });

  final String port;
  final String name;
  final String systemId;
}
