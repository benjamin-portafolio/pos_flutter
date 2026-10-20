import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../application/weighing/scale_exception.dart';
import '../../application/weighing/scale_failure.dart';
import 'rhino_bar8rs_protocol.dart';

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class _DeviceInfo extends Struct {
  @Uint32()
  external int size;
  external _Guid guid;
  @Uint32()
  external int device;
  @UintPtr()
  external int reserved;
}

final class _Dcb extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int baudRate;
  @Uint32()
  external int flags;
  @Uint16()
  external int reserved;
  @Uint16()
  external int xonLimit;
  @Uint16()
  external int xoffLimit;
  @Uint8()
  external int byteSize;
  @Uint8()
  external int parity;
  @Uint8()
  external int stopBits;
  @Int8()
  external int xonChar;
  @Int8()
  external int xoffChar;
  @Int8()
  external int errorChar;
  @Int8()
  external int eofChar;
  @Int8()
  external int eventChar;
  @Uint16()
  external int reserved1;
}

final class _Timeouts extends Struct {
  @Uint32()
  external int readInterval;
  @Uint32()
  external int readMultiplier;
  @Uint32()
  external int readConstant;
  @Uint32()
  external int writeMultiplier;
  @Uint32()
  external int writeConstant;
}

/// Windows system APIs only; no bundled DLL, plugin or serial SDK. Called only
/// from WindowsScaleGateway worker isolates. No library loads at import time.
Object? windowsScaleNative(String operation, Map<String, Object?> args) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final lastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true,
  );
  // Resolve the FFI invocation before an API sets its thread-local error.
  // In a cold Flutter debug isolate, first-call resolution otherwise clobbers
  // ERROR_NO_MORE_ITEMS and makes successful enumeration fail with code zero.
  lastError();
  if (operation == 'list') return _listPorts(lastError);
  final close = kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  return using((arena) {
    switch (operation) {
      case 'open':
        final create = kernel
            .lookupFunction<
              IntPtr Function(
                Pointer<Utf16>,
                Uint32,
                Uint32,
                Pointer<Void>,
                Uint32,
                Uint32,
                IntPtr,
              ),
              int Function(
                Pointer<Utf16>,
                int,
                int,
                Pointer<Void>,
                int,
                int,
                int,
              )
            >('CreateFileW');
        final handle = create(
          '\\\\.\\${args['port']}'.toNativeUtf16(allocator: arena),
          0xC0000000,
          0,
          nullptr,
          3,
          0,
          0,
        );
        if (handle == -1) {
          final code = lastError();
          throw ScaleException(switch (code) {
            2 || 3 || 1167 => ScaleFailure.deviceNotFound,
            5 => ScaleFailure.accessDenied,
            32 => ScaleFailure.busy,
            _ => ScaleFailure.connectionFailed,
          }, nativeCode: code);
        }
        final getState = kernel
            .lookupFunction<
              Int32 Function(IntPtr, Pointer<_Dcb>),
              int Function(int, Pointer<_Dcb>)
            >('GetCommState');
        final setState = kernel
            .lookupFunction<
              Int32 Function(IntPtr, Pointer<_Dcb>),
              int Function(int, Pointer<_Dcb>)
            >('SetCommState');
        final setTimeouts = kernel
            .lookupFunction<
              Int32 Function(IntPtr, Pointer<_Timeouts>),
              int Function(int, Pointer<_Timeouts>)
            >('SetCommTimeouts');
        final purge = kernel
            .lookupFunction<
              Int32 Function(IntPtr, Uint32),
              int Function(int, int)
            >('PurgeComm');
        final dcb = arena<_Dcb>();
        dcb.ref.length = sizeOf<_Dcb>();
        var configured = getState(handle, dcb) != 0;
        if (configured) {
          dcb.ref.baudRate = args['baudRate'] as int;
          dcb.ref.byteSize = args['dataBits'] as int;
          dcb.ref.parity = args['parity'] as int;
          dcb.ref.stopBits = (args['stopBits'] as int) - 1; // ONESTOPBIT = 0.
          dcb.ref.flags =
              1; // fBinary; no parity, DTR/RTS, CTS/DSR or XON/XOFF.
          configured = setState(handle, dcb) != 0;
        }
        if (configured) {
          final timeouts = arena<_Timeouts>();
          // Documented MAXDWORD/MAXDWORD mode: return available bytes, or
          // wait at most 50ms for the first byte. Write deadline is native too.
          timeouts.ref.readInterval = 0xFFFFFFFF;
          timeouts.ref.readMultiplier = 0xFFFFFFFF;
          timeouts.ref.readConstant = 50;
          timeouts.ref.writeConstant = 300;
          configured = setTimeouts(handle, timeouts) != 0;
        }
        if (configured) configured = purge(handle, 0x0C) != 0;
        return <String, Object?>{
          'handle': handle,
          'configured': configured,
          if (!configured) 'error': lastError(),
        };
      case 'query':
        final write = kernel
            .lookupFunction<
              Int32 Function(
                IntPtr,
                Pointer<Uint8>,
                Uint32,
                Pointer<Uint32>,
                Pointer<Void>,
              ),
              int Function(
                int,
                Pointer<Uint8>,
                int,
                Pointer<Uint32>,
                Pointer<Void>,
              )
            >('WriteFile');
        final read = kernel
            .lookupFunction<
              Int32 Function(
                IntPtr,
                Pointer<Uint8>,
                Uint32,
                Pointer<Uint32>,
                Pointer<Void>,
              ),
              int Function(
                int,
                Pointer<Uint8>,
                int,
                Pointer<Uint32>,
                Pointer<Void>,
              )
            >('ReadFile');
        final handle = args['handle'] as int;
        final buffer = arena<Uint8>(128);
        buffer.value = RhinoBar8RsProtocol.weightRequest.single;
        final count = arena<Uint32>();
        if (write(handle, buffer, 1, count, nullptr) == 0 || count.value != 1) {
          throw ScaleException(
            ScaleFailure.transportError,
            nativeCode: lastError(),
          );
        }
        final result = <int>[];
        final timer = Stopwatch()..start();
        // At most one request and 128 response bytes. Native calls are bounded;
        // close awaits this entire operation, including any current read slice.
        while (timer.elapsedMilliseconds < 700 && result.length < 128) {
          if (read(handle, buffer, 128 - result.length, count, nullptr) == 0) {
            throw ScaleException(
              ScaleFailure.transportError,
              nativeCode: lastError(),
            );
          }
          result.addAll(buffer.asTypedList(count.value));
          if (result.contains(13)) break;
        }
        return result;
      case 'close':
        return close(args['handle'] as int) != 0;
      default:
        throw ArgumentError.value(operation);
    }
  });
}

List<Map<String, Object?>> _listPorts(int Function() lastError) {
  final setup = DynamicLibrary.open('setupapi.dll');
  final registry = DynamicLibrary.open('advapi32.dll');
  final getClass = setup
      .lookupFunction<
        IntPtr Function(Pointer<_Guid>, Pointer<Utf16>, IntPtr, Uint32),
        int Function(Pointer<_Guid>, Pointer<Utf16>, int, int)
      >('SetupDiGetClassDevsW');
  final enumerate = setup
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<_DeviceInfo>),
        int Function(int, int, Pointer<_DeviceInfo>)
      >('SetupDiEnumDeviceInfo');
  final destroy = setup
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetupDiDestroyDeviceInfoList',
      );
  final openKey = setup
      .lookupFunction<
        IntPtr Function(
          IntPtr,
          Pointer<_DeviceInfo>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
        ),
        int Function(int, Pointer<_DeviceInfo>, int, int, int, int)
      >('SetupDiOpenDevRegKey');
  final query = registry
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        )
      >('RegQueryValueExW');
  final closeKey = registry
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');
  final property = setup
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<_DeviceInfo>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<_DeviceInfo>,
          int,
          Pointer<Uint32>,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
        )
      >('SetupDiGetDeviceRegistryPropertyW');
  final instanceId = setup
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<_DeviceInfo>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<_DeviceInfo>,
          Pointer<Utf16>,
          int,
          Pointer<Uint32>,
        )
      >('SetupDiGetDeviceInstanceIdW');
  return using((arena) {
    // GUID_DEVCLASS_PORTS. Only present devices, with a real COM PortName.
    final guid = arena<_Guid>();
    guid.ref.data1 = 0x4D36E978;
    guid.ref.data2 = 0xE325;
    guid.ref.data3 = 0x11CE;
    final tail = [0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18];
    for (var i = 0; i < tail.length; i++) {
      guid.ref.data4[i] = tail[i];
    }
    final devices = getClass(guid, nullptr, 0, 2);
    if (devices == -1) {
      throw ScaleException(
        ScaleFailure.transportError,
        nativeCode: lastError(),
      );
    }
    final result = <Map<String, Object?>>[];
    try {
      final info = arena<_DeviceInfo>();
      final portBuffer = arena<Uint8>(256);
      final nameBuffer = arena<Uint8>(2048);
      final idBuffer = arena<Uint16>(1024).cast<Utf16>();
      final needed = arena<Uint32>();
      final type = arena<Uint32>();
      final portKey = 'PortName'.toNativeUtf16(allocator: arena);
      for (var index = 0; ; index++) {
        info.ref.size = sizeOf<_DeviceInfo>();
        if (enumerate(devices, index, info) == 0) {
          final code = lastError();
          if (code == 259) break;
          throw ScaleException(ScaleFailure.transportError, nativeCode: code);
        }
        final key = openKey(devices, info, 1, 0, 1, 0x20019);
        if (key == -1) continue;
        String? port;
        try {
          needed.value = 256;
          if (query(key, portKey, nullptr, type, portBuffer, needed) == 0 &&
              type.value == 1 &&
              needed.value >= 2 &&
              needed.value <= 256) {
            port = portBuffer.cast<Utf16>().toDartString(
              length: needed.value ~/ 2 - 1,
            );
          }
        } finally {
          closeKey(key);
        }
        if (port == null || !RegExp(r'^COM[1-9][0-9]*$').hasMatch(port)) {
          continue;
        }
        if (instanceId(devices, info, idBuffer, 1024, needed) == 0) {
          throw ScaleException(
            ScaleFailure.transportError,
            nativeCode: lastError(),
          );
        }
        var name = port;
        if (property(devices, info, 12, type, nameBuffer, 2048, needed) != 0 &&
            type.value == 1 &&
            needed.value >= 2 &&
            needed.value <= 2048) {
          name = nameBuffer.cast<Utf16>().toDartString(
            length: needed.value ~/ 2 - 1,
          );
        }
        result.add({
          'port': port,
          'name': name,
          'systemId': idBuffer.toDartString(),
        });
      }
    } finally {
      destroy(devices);
    }
    result.sort((a, b) => (a['port'] as String).compareTo(b['port'] as String));
    return result;
  });
}
