import 'dart:async';

import 'package:pos_flutter/application/weighing/scale_device.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_gateway.dart';
import 'package:pos_flutter/application/weighing/scale_measurement.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';

class FakeScaleGateway implements ScaleGateway {
  final calls = <String>[];
  final reads = <Completer<List<ScaleMeasurement>>>[];
  Completer<void>? pendingOpen;
  Completer<void>? pendingClose;
  bool failClose = false;
  List<ScaleDevice> devices = [];
  ScaleFailure? listFailure;

  @override
  Future<List<ScaleDevice>> listDevices() async {
    calls.add('list');
    if (listFailure case final failure?) throw ScaleException(failure);
    return devices;
  }

  @override
  Future<void> open(ScaleProfile profile) async {
    calls.add('open:${profile.port}');
    await pendingOpen?.future;
  }

  @override
  Future<List<ScaleMeasurement>> readWeight() {
    calls.add('query');
    final pending = Completer<List<ScaleMeasurement>>();
    reads.add(pending);
    return pending.future;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    await pendingClose?.future;
    if (failClose) throw const ScaleException(ScaleFailure.closeFailed);
  }
}
