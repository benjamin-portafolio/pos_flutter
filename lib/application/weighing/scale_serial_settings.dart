/// Only the serial parameters used by the initial, verified Rhino adapter.
class ScaleSerialSettings {
  const ScaleSerialSettings({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = 0,
    this.stopBits = 1,
  });

  final int baudRate;
  final int dataBits;
  // Win32 parity: 0 = none. No hardware/software flow control is enabled.
  final int parity;
  final int stopBits;

  bool get isRhinoCompatible =>
      baudRate == 9600 && dataBits == 8 && parity == 0 && stopBits == 1;
}
