import 'dart:typed_data';

/// Monochrome raster, MSB first, one bit per dot; 1 prints black.
class ThermalTicketBand {
  ThermalTicketBand({
    required this.width,
    required this.height,
    required Uint8List raster,
  }) : raster = raster.asUnmodifiableView();

  final int width;
  final int height;
  final Uint8List raster;
}
