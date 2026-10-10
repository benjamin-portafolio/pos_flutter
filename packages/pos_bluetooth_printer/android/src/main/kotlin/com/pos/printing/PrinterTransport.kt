package com.pos.printing

import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal interface PrinterSocket {
    fun connect()
    fun write(bytes: ByteArray, offset: Int, count: Int)
    fun flush()
    fun close()
}

internal class TransportFailure(val code: String) : Exception(code)

/** Owns exactly one SPP socket. Close aborts on a separate executor and then
 * waits for the I/O worker: returning from close is a termination barrier.
 * A stuck/failed close keeps the transport unavailable for another send. */
internal class PrinterTransport(
    private val pauseBetweenBlocks: () -> Unit = { Thread.sleep(40) },
    private val createSocket: (String) -> PrinterSocket
) {
    private val gate = Any()
    private val worker = Executors.newSingleThreadExecutor()
    private val closer = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private var socket: PrinterSocket? = null
    private var busy = false
    private var closing = false
    private var closeFuture: CompletableFuture<Unit>? = null

    fun connect(address: String, timeoutMs: Long = 10_000): CompletableFuture<Unit> =
        operation(timeoutMs, "connection_failed") {
            // Never reuse the previous destination, including after a failed attempt.
            val previous = synchronized(gate) { socket }
            previous?.close()
            synchronized(gate) { socket = null }
            val candidate = createSocket(address)
            synchronized(gate) {
                socket = candidate
                if (closing) throw TransportFailure("timeout")
            }
            candidate.connect()
        }

    fun write(bytes: ByteArray, timeoutMs: Long = 20_000): CompletableFuture<Unit> {
        val snapshot = bytes.copyOf()
        return operation(timeoutMs, "write_failed") {
            val destination = synchronized(gate) { socket }
                ?: throw TransportFailure("connection_failed")
            var offset = 0
            while (offset < snapshot.size) {
                synchronized(gate) {
                    if (closing) throw TransportFailure("timeout")
                }
                val count = minOf(256, snapshot.size - offset)
                destination.write(snapshot, offset, count)
                offset += count
                // Include the last block: completing write must not let the
                // next raster band immediately burst into the receiver buffer.
                // This is pacing, not an acknowledgement of physical printing.
                pauseBetweenBlocks()
            }
            synchronized(gate) {
                if (closing) throw TransportFailure("timeout")
            }
            destination.flush()
        }
    }

    private fun operation(timeoutMs: Long, failureCode: String,
                          action: () -> Unit): CompletableFuture<Unit> {
        val result = CompletableFuture<Unit>()
        synchronized(gate) {
            if (busy || closing) {
                result.completeExceptionally(TransportFailure("busy"))
                return result
            }
            busy = true
            val expired = AtomicBoolean(false)
            val deadline = timer.schedule({
                synchronized(gate) {
                    if (!result.isDone) {
                        expired.set(true)
                        close()
                    }
                }
            }, timeoutMs, TimeUnit.MILLISECONDS)
            worker.execute {
                var failure: Throwable? = null
                try {
                    action()
                } catch (error: Throwable) {
                    failure = if (error is TransportFailure || error is SecurityException) error else TransportFailure(failureCode)
                }
                synchronized(gate) {
                    deadline.cancel(false)
                    busy = false
                    if (expired.get()) failure = TransportFailure("timeout")
                    if (failure == null) result.complete(Unit)
                    else result.completeExceptionally(failure)
                }
            }
        }
        return result
    }

    fun close(): CompletableFuture<Unit> = synchronized(gate) {
        closeFuture?.let { return it }
        closing = true
        val result = CompletableFuture<Unit>()
        closeFuture = result
        val captured = socket
        val abort = CompletableFuture<Unit>()
        closer.execute {
            try {
                captured?.close()
                abort.complete(Unit)
            } catch (error: Throwable) {
                abort.completeExceptionally(error)
            }
        }
        worker.execute {
            try {
                // Wait for the abort caller too, even when I/O completed sooner.
                abort.join()
                // Captures a socket created after close began. No future connect
                // or write is admitted while this barrier is outstanding.
                val remaining = synchronized(gate) { socket }
                if (remaining !== captured) remaining?.close()
                synchronized(gate) {
                    socket = null
                    closing = false
                    closeFuture = null
                    result.complete(Unit)
                }
            } catch (error: Throwable) {
                synchronized(gate) {
                    // Retain socket and quarantine; an explicit close can retry.
                    closeFuture = null
                    result.completeExceptionally(TransportFailure("close_failed"))
                }
            }
        }
        result
    }

    fun shutdown() {
        close().whenComplete { _, _ ->
            timer.shutdownNow()
            closer.shutdown()
            worker.shutdown()
        }
    }
}
