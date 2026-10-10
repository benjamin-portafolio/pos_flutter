import 'dart:async';
import 'package:pos_flutter/application/printing/printer_device.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';

class FakePrinterGateway implements PrinterGateway {
  PrinterAvailability state = PrinterAvailability.ready;
  PrinterPermission permission = PrinterPermission.granted;
  PrinterPermission requestedPermission = PrinterPermission.granted;
  List<PrinterDevice> devices = [
    const PrinterDevice(address: 'AA:BB:CC:DD:EE:01', name: 'Same name'),
    const PrinterDevice(address: 'AA:BB:CC:DD:EE:02', name: 'Same name'),
  ];
  final calls = <String>[];
  final writes = <List<int>>[];
  Completer<void>? pendingConnect;
  Completer<void>? pendingWrite;
  Completer<void>? pendingClose;
  Completer<PrinterPermission>? pendingPermission;
  PrinterFailure? connectFailure;
  PrinterFailure? writeFailure;
  PrinterFailure? closeFailure;
  @override
  Future<PrinterAvailability> availability() async {
    calls.add('availability');
    return state;
  }

  @override
  Future<PrinterPermission> permissionStatus() async {
    calls.add('permissionStatus');
    return permission;
  }

  @override
  Future<PrinterPermission> requestPermission() async {
    calls.add('requestPermission');
    return pendingPermission?.future ?? requestedPermission;
  }

  @override
  Future<List<PrinterDevice>> bondedDevices() async {
    calls.add('bondedDevices');
    return devices;
  }

  @override
  Future<void> connect(String address) async {
    calls.add('connect:$address');
    if (connectFailure case final failure?) throw PrinterException(failure);
    await pendingConnect?.future;
  }

  @override
  Future<void> write(List<int> bytes) async {
    calls.add('write');
    writes.add(bytes);
    if (writeFailure case final failure?) throw PrinterException(failure);
    await pendingWrite?.future;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    if (closeFailure case final failure?) throw PrinterException(failure);
    await pendingClose?.future;
  }
}
