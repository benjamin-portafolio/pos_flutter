/// A paired device is not proof of ESC/POS compatibility.
class PrinterDevice {
  const PrinterDevice({required this.address, required this.name});
  final String address;
  final String? name;
}
