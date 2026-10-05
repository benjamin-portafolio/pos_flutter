import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Sustituye solo la cámara nativa; los widgets y el controller son reales.
class FakeMobileScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  Exception? startError;
  Completer<void>? startGate;
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  StartOptions? lastStartOptions;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Widget buildCameraView() =>
      const SizedBox(key: Key('fake_camera_preview'), width: 640, height: 480);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    lastStartOptions = startOptions;
    await startGate?.future;
    if (startError case final error?) throw error;
    return MobileScannerViewAttributes(
      cameraDirection: startOptions.cameraDirection,
      currentTorchMode: TorchState.off,
      size: const Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
