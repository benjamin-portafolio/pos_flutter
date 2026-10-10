import 'dart:async';

import '../tickets/ticket_document.dart';
import 'printer_exception.dart';
import 'printer_gateway.dart';
import 'printer_profile.dart';
import 'printer_test_payload.dart';
import 'ticket_print_result.dart';
import 'ticket_encoder.dart';

/// One shared instance in DI owns every print, including configuration probes.
/// A deadline reports to the caller but retains ownership of the original
/// future and cleanup. Requests are rejected, never queued or retried.
class TicketPrintService {
  TicketPrintService(
    this._gateway, {
    TicketEncoder? encoder,
    this.generationTimeout = const Duration(seconds: 30),
    this.permissionTimeout = const Duration(seconds: 35),
    this.connectionTimeout = const Duration(seconds: 15),
    this.writeTimeout = const Duration(seconds: 30),
    this.closeTimeout = const Duration(seconds: 10),
  }) : _encoder = encoder;

  final PrinterGateway _gateway;
  final TicketEncoder? _encoder;
  final Duration generationTimeout;
  final Duration permissionTimeout;
  final Duration connectionTimeout;
  final Duration writeTimeout;
  final Duration closeTimeout;
  Future<void>? _active;
  bool _stopping = false;
  bool _unsafeClose = false;
  bool get isBusy => _active != null || _unsafeClose;
  final _busyChanges = StreamController<bool>.broadcast(sync: true);
  Stream<bool> get busyChanges => _busyChanges.stream;

  Future<TicketPrintResult> printTest(
    PrinterProfile profile, {
    Future<bool> Function()? beforeSend,
    bool Function()? isActive,
  }) => printTicket(
    document: PrinterTestPayload.create(profile),
    profile: profile,
    beforeSend: beforeSend,
    isActive: isActive,
  );

  Future<TicketPrintResult> printTicket({
    required TicketDocument document,
    required PrinterProfile profile,
    Future<bool> Function()? beforeSend,
    bool Function()? isActive,
  }) => _start(
    profile,
    () {
      final encoder = _encoder;
      if (encoder == null) {
        throw const PrinterException(PrinterFailure.generationFailed);
      }
      // Both inputs are deeply immutable snapshots captured by the caller.
      return encoder.encode(document, profile);
    },
    beforeSend: beforeSend,
    isActive: isActive,
  );

  Future<TicketPrintResult> send({
    required PrinterProfile profile,
    required List<int> bytes,
  }) {
    if (bytes.isEmpty || bytes.any((b) => b < 0 || b > 255)) {
      return Future.value(
        const TicketPrintResult(failure: PrinterFailure.writeFailed),
      );
    }
    final snapshot = List<int>.unmodifiable(bytes);
    return _start(profile, () async* {
      yield snapshot;
    });
  }

  Future<TicketPrintResult> _start(
    PrinterProfile profile,
    Stream<List<int>> Function() chunks, {
    Future<bool> Function()? beforeSend,
    bool Function()? isActive,
  }) {
    if (_stopping) {
      return Future.value(
        const TicketPrintResult(failure: PrinterFailure.disposed),
      );
    }
    if (isBusy) {
      return Future.value(
        const TicketPrintResult(failure: PrinterFailure.busy),
      );
    }
    final response = Completer<TicketPrintResult>();
    final done = Completer<void>();
    _active = done.future;
    _busyChanges.add(true);
    _perform(profile, chunks, response, beforeSend, isActive).then((result) {
      _active = null;
      done.complete();
      _busyChanges.add(isBusy);
      if (!response.isCompleted) response.complete(result);
    });
    return response.future;
  }

  Future<TicketPrintResult> _perform(
    PrinterProfile profile,
    Stream<List<int>> Function() chunks,
    Completer<TicketPrintResult> response,
    Future<bool> Function()? beforeSend,
    bool Function()? isActive,
  ) async {
    var writeStarted = false;
    var connectionAttempted = false;
    PrinterFailure? failure;
    StreamIterator<List<int>>? iterator;
    var iteratorCompleted = false;
    Future<bool> nextBand() async {
      try {
        final next = await iterator!.moveNext();
        if (!next) iteratorCompleted = true;
        return next;
      } catch (_) {
        // StreamIterator cancels its subscription on an error.
        iteratorCompleted = true;
        rethrow;
      }
    }

    void checkIntent() {
      if (_stopping) throw const PrinterException(PrinterFailure.disposed);
      if (!writeStarted && isActive != null && !isActive()) {
        throw const PrinterException(PrinterFailure.canceled);
      }
    }

    Future<T> step<T>(
      Future<T> operation,
      Duration limit, {
      bool cleanup = false,
    }) async {
      try {
        return await operation.timeout(limit);
      } on TimeoutException {
        if (!response.isCompleted) {
          response.complete(
            TicketPrintResult(
              failure: PrinterFailure.timeout,
              writeStarted: writeStarted,
            ),
          );
        }
        // timeout does not cancel I/O. Drain even a late error, then stop this
        // attempt before another stage can write. Cleanup still owns the lock.
        if (cleanup) return await operation;
        try {
          await operation;
        } catch (_) {
          /* Original failure is drained. */
        }
        throw const PrinterException(PrinterFailure.timeout);
      }
    }

    try {
      checkIntent();
      if (beforeSend != null) {
        if (!await step(Future.sync(beforeSend), permissionTimeout)) {
          throw const PrinterException(PrinterFailure.canceled);
        }
        checkIntent();
      }
      var availability = await step(_gateway.availability(), permissionTimeout);
      checkIntent();
      if (availability == PrinterAvailability.unsupported) {
        throw const PrinterException(PrinterFailure.unsupportedPlatform);
      }
      if (availability == PrinterAvailability.noHardware) {
        throw const PrinterException(PrinterFailure.hardwareUnavailable);
      }
      var permission = await step(
        _gateway.permissionStatus(),
        permissionTimeout,
      );
      checkIntent();
      if (permission == PrinterPermission.denied) {
        permission = await step(
          _gateway.requestPermission(),
          permissionTimeout,
        );
        checkIntent();
      }
      if (permission != PrinterPermission.granted) {
        throw PrinterException(
          permission == PrinterPermission.permanentlyDenied
              ? PrinterFailure.permissionPermanentlyDenied
              : PrinterFailure.permissionDenied,
        );
      }
      availability = await step(_gateway.availability(), permissionTimeout);
      checkIntent();
      if (availability != PrinterAvailability.ready) {
        throw PrinterException(switch (availability) {
          PrinterAvailability.off => PrinterFailure.bluetoothOff,
          PrinterAvailability.noHardware => PrinterFailure.hardwareUnavailable,
          PrinterAvailability.unsupported => PrinterFailure.unsupportedPlatform,
          _ => PrinterFailure.permissionDenied,
        });
      }
      final devices = await step(
        _gateway.listDestinations(),
        permissionTimeout,
      );
      checkIntent();
      if (!devices.any(
        (d) =>
            d.transport == profile.transport &&
            (profile.transport == PrinterTransport.androidBluetooth
                ? d.address.toUpperCase() == profile.address
                : d.address == profile.address),
      )) {
        throw const PrinterException(PrinterFailure.deviceNotBonded);
      }
      try {
        iterator = StreamIterator(chunks());
      } catch (_) {
        throw const PrinterException(PrinterFailure.generationFailed);
      }
      var count = 0;
      while (true) {
        bool next;
        try {
          next = await step(nextBand(), generationTimeout);
        } on PrinterException {
          rethrow;
        } catch (_) {
          throw const PrinterException(PrinterFailure.generationFailed);
        }
        checkIntent();
        if (!next) break;
        final bytes = iterator.current;
        if (bytes.isEmpty || bytes.any((b) => b < 0 || b > 255)) {
          throw const PrinterException(PrinterFailure.generationFailed);
        }
        if (!connectionAttempted) {
          connectionAttempted = true;
          await step(_gateway.connect(profile.address), connectionTimeout);
          checkIntent();
        }
        writeStarted = true;
        await step(_gateway.write(bytes), writeTimeout);
        count++;
      }
      if (count == 0) {
        throw const PrinterException(PrinterFailure.generationFailed);
      }
    } on PrinterException catch (error) {
      failure = error.failure;
    } catch (_) {
      failure = PrinterFailure.transportError;
    } finally {
      try {
        if (iterator != null && !iteratorCompleted) await iterator.cancel();
      } catch (_) {
        failure ??= PrinterFailure.generationFailed;
      }
      if (connectionAttempted) {
        try {
          await step(
            _gateway is PrinterJobGateway
                ? (_gateway as PrinterJobGateway).finishJob(
                    commit: failure == null,
                  )
                : _gateway.close(),
            closeTimeout,
            cleanup: true,
          );
        } on PrinterException catch (error) {
          failure ??= error.failure;
          // Close failed, so retain a quarantine until explicit shutdown
          // recovery actually closes the connection.
          _unsafeClose = true;
        } catch (_) {
          failure ??= PrinterFailure.closeFailed;
          _unsafeClose = true;
        }
      }
    }
    return TicketPrintResult(failure: failure, writeStarted: writeStarted);
  }

  /// Called before DI reset. Stops new requests, drains pending native I/O,
  /// and awaits actual close; an error prevents dependency replacement.
  Future<void> dispose() async {
    _stopping = true;
    await _active;
    await _gateway.close();
    _unsafeClose = false;
    await _busyChanges.close();
  }
}
