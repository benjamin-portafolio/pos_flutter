import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../application/printing/printer_exception.dart';

final class _DocInfo extends Struct {
  external Pointer<Utf16> name;
  external Pointer<Utf16> output;
  external Pointer<Utf16> datatype;
}

final class _PrinterInfo4 extends Struct {
  external Pointer<Utf16> name;
  external Pointer<Utf16> server;
  @Uint32()
  external int attributes;
}

/// Invoked only inside WindowsPrinterGateway's worker isolates. Uses installed
/// local queues (including USB001), never opens a USB device or network socket.
Object? windowsPrinterNative(String operation, Map<String, Object?> args) {
  final dll = DynamicLibrary.open('winspool.drv');
  final close = dll.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'ClosePrinter',
  );
  final abort = dll.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'AbortPrinter',
  );
  final end = dll.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'EndDocPrinter',
  );
  return using((arena) {
    switch (operation) {
      case 'list':
        final getLastError = DynamicLibrary.open(
          'kernel32.dll',
        ).lookupFunction<Uint32 Function(), int Function()>('GetLastError');
        final enumerate = dll
            .lookupFunction<
              Int32 Function(
                Uint32,
                Pointer<Utf16>,
                Uint32,
                Pointer<Uint8>,
                Uint32,
                Pointer<Uint32>,
                Pointer<Uint32>,
              ),
              int Function(
                int,
                Pointer<Utf16>,
                int,
                Pointer<Uint8>,
                int,
                Pointer<Uint32>,
                Pointer<Uint32>,
              )
            >('EnumPrintersW');
        final needed = arena<Uint32>();
        final count = arena<Uint32>();
        final first = enumerate(2, nullptr, 4, nullptr, 0, needed, count);
        if (first == 0) {
          final error = getLastError();
          if (error != 122) {
            throw const PrinterException(PrinterFailure.transportError);
          }
        }
        if (needed.value == 0) return <String>[];
        final buffer = arena<Uint8>(needed.value);
        if (enumerate(2, nullptr, 4, buffer, needed.value, needed, count) ==
            0) {
          throw const PrinterException(PrinterFailure.transportError);
        }
        final printers = buffer.cast<_PrinterInfo4>();
        return [
          for (var i = 0; i < count.value; i++) printers[i].name.toDartString(),
        ];
      case 'open':
        final open = dll
            .lookupFunction<
              Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
              int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
            >('OpenPrinterW');
        final start = dll
            .lookupFunction<
              Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo>),
              int Function(int, int, Pointer<_DocInfo>)
            >('StartDocPrinterW');
        final handle = arena<IntPtr>();
        final name = (args['name'] as String).toNativeUtf16(allocator: arena);
        if (open(name, handle, nullptr) == 0) {
          throw const PrinterException(PrinterFailure.connectionFailed);
        }
        final doc = arena<_DocInfo>();
        doc.ref.name = 'Ticket POS'.toNativeUtf16(allocator: arena);
        doc.ref.output = nullptr;
        doc.ref.datatype = 'RAW'.toNativeUtf16(allocator: arena);
        final started = start(handle.value, 1, doc) != 0;
        return <String, Object?>{'handle': handle.value, 'started': started};
      case 'write':
        final write = dll
            .lookupFunction<
              Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
              int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
            >('WritePrinter');
        final bytes = args['bytes'] as List<int>;
        final data = arena<Uint8>(bytes.length);
        data.asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        if (write(args['handle'] as int, data, bytes.length, written) == 0 ||
            written.value != bytes.length) {
          // Partial writes are ambiguous: fail and abort, never resend bytes.
          throw const PrinterException(PrinterFailure.writeFailed);
        }
        return null;
      case 'finish':
        final handle = args['handle'] as int;
        var failed = false;
        if (args['documentOpen'] == true) {
          failed = (args['commit'] == true ? end(handle) : abort(handle)) == 0;
        }
        final closed = close(handle) != 0;
        return <String, Object?>{'closed': closed, 'failed': failed || !closed};
      default:
        throw ArgumentError.value(operation);
    }
  });
}
