package com.pos.printing

import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

class PrinterTransportTest {
    private class Socket : PrinterSocket {
        val events = Collections.synchronizedList(mutableListOf<String>())
        var onConnect: () -> Unit = {}
        var onWrite: () -> Unit = {}
        var onFlush: () -> Unit = {}
        var onClose: () -> Unit = {}
        val output = Collections.synchronizedList(mutableListOf<Byte>())
        override fun connect() { events.add("connect"); onConnect() }
        override fun write(bytes: ByteArray, offset: Int, count: Int) {
            events.add("write:$count"); onWrite()
            output.addAll(bytes.slice(offset until offset + count))
        }
        override fun flush() { events.add("flush"); onFlush() }
        override fun close() { events.add("close"); onClose() }
    }
    private fun await(latch: CountDownLatch) { assertTrue(latch.await(3, TimeUnit.SECONDS)) }
    private fun done(future: CompletableFuture<Unit>) { future.get(3, TimeUnit.SECONDS) }
    private fun failure(future: CompletableFuture<Unit>, code: String) {
        try { done(future); fail("Expected $code") }
        catch (error: ExecutionException) {
            assertEquals(code, (error.cause as TransportFailure).code)
        }
    }

    @Test fun permissionPolicyCoversLegacyDenialPermanentAndRevocation() {
        assertEquals("granted", PrinterPermissionPolicy.status(30, false, false, false))
        assertEquals("denied", PrinterPermissionPolicy.status(31, false, false, false))
        assertEquals("granted", PrinterPermissionPolicy.status(35, true, true, false))
        assertEquals("denied", PrinterPermissionPolicy.status(35, false, true, true))
        assertEquals("permanently_denied", PrinterPermissionPolicy.status(35, false, true, false))
    }

    @Test fun writeCompletionWaitsForFlushAndPreservesBytesAcrossBands() {
        val socket = Socket()
        val flushing = CountDownLatch(1)
        val allowFlush = CountDownLatch(1)
        socket.onFlush = { flushing.countDown(); await(allowFlush) }
        val transport = PrinterTransport { socket }
        try {
            done(transport.connect("A"))
            val bytes = ByteArray(2050) { (it % 256).toByte() }
            val expected = bytes.toList()
            val writing = transport.write(bytes)
            bytes.fill(0)
            await(flushing)
            assertFalse(writing.isDone)
            failure(transport.write(byteArrayOf(1)), "busy")
            allowFlush.countDown()
            done(writing)
            assertEquals(expected, socket.output)
            assertEquals(listOf("connect") + List(8) { "write:256" } + listOf("write:2", "flush"), socket.events)
            done(transport.close())
        } finally { allowFlush.countDown(); transport.shutdown() }
    }

    @Test fun finalBlockPauseKeepsWritePendingAndRejectsFollowingBand() {
        val socket = Socket()
        val paused = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = PrinterTransport(pauseBetweenBlocks = {
            paused.countDown(); await(release)
        }) { socket }
        try {
            done(transport.connect("A"))
            val writing = transport.write(byteArrayOf(1))
            await(paused)
            assertFalse(writing.isDone)
            assertEquals(listOf("connect", "write:1"), socket.events)
            failure(transport.write(byteArrayOf(2)), "busy")
            failure(transport.connect("B"), "busy")
            release.countDown()
            done(writing)
            done(transport.write(byteArrayOf(2)))
            assertEquals(listOf<Byte>(1, 2), socket.output)
            done(transport.close())
        } finally { release.countDown(); transport.shutdown() }
    }

    @Test fun everyBlockIncludingLastIsPacedAndCloseAbortsDuringPause() {
        val socket = Socket()
        val paused = CountDownLatch(1)
        val release = CountDownLatch(1)
        val closed = CountDownLatch(1)
        socket.onClose = { closed.countDown() }
        var pauses = 0
        val transport = PrinterTransport(pauseBetweenBlocks = {
            pauses++
            if (pauses == 3) { paused.countDown(); await(release) }
        }) { socket }
        try {
            done(transport.connect("A"))
            val bytes = ByteArray(513) { (it % 256).toByte() }
            val writing = transport.write(bytes)
            await(paused)
            assertEquals(3, pauses)
            assertEquals(listOf("connect", "write:256", "write:256", "write:1"), socket.events)
            assertEquals(bytes.toList(), socket.output)
            val close = transport.close()
            await(closed)
            assertFalse(close.isDone)
            failure(transport.connect("B"), "busy")
            release.countDown()
            failure(writing, "timeout")
            done(close)
            assertFalse(socket.events.contains("flush"))
        } finally { release.countDown(); transport.shutdown() }
    }

    @Test fun nativeDeadlineClosesToAbortButRemainsBusyUntilWriteAndCloseFinish() {
        val socket = Socket()
        val writing = CountDownLatch(1)
        val closing = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val releaseClose = CountDownLatch(1)
        socket.onWrite = { writing.countDown(); await(releaseWrite); throw IOException("aborted") }
        socket.onClose = { closing.countDown(); await(releaseClose); releaseWrite.countDown() }
        val transport = PrinterTransport { socket }
        try {
            done(transport.connect("A"))
            val operation = transport.write(byteArrayOf(1), 40)
            await(writing); await(closing)
            assertFalse(operation.isDone)
            val close = transport.close()
            assertFalse(close.isDone)
            failure(transport.connect("B"), "busy")
            releaseClose.countDown()
            failure(operation, "timeout")
            done(close)
            socket.onConnect = {}
            done(transport.connect("B"))
        } finally { releaseWrite.countDown(); releaseClose.countDown(); transport.shutdown() }
    }

    @Test fun closeBarrierAlsoWaitsWhenAbortReturnsBeforeNativeWriteTerminates() {
        val socket = Socket()
        val writing = CountDownLatch(1)
        val aborted = CountDownLatch(1)
        val release = CountDownLatch(1)
        socket.onWrite = { writing.countDown(); await(release); throw IOException("closed") }
        socket.onClose = { aborted.countDown() }
        val transport = PrinterTransport { socket }
        try {
            done(transport.connect("A"))
            val operation = transport.write(byteArrayOf(1))
            await(writing)
            val close = transport.close(); await(aborted)
            assertFalse(close.isDone)
            failure(transport.connect("B"), "busy")
            release.countDown()
            failure(operation, "write_failed"); done(close)
        } finally { release.countDown(); transport.shutdown() }
    }

    @Test fun timedOutConnectIsAbortedAndClosedBeforeAnotherDestination() {
        val socket = Socket()
        val connecting = CountDownLatch(1)
        val closed = CountDownLatch(1)
        socket.onConnect = { connecting.countDown(); await(closed); throw IOException("closed") }
        socket.onClose = { closed.countDown() }
        val transport = PrinterTransport { socket }
        try {
            val connection = transport.connect("A", 40)
            await(connecting)
            failure(connection, "timeout")
            done(transport.close())
            assertEquals(listOf("connect", "close"), socket.events)
        } finally { closed.countDown(); transport.shutdown() }
    }

    @Test fun socketCreatedAfterCloseBeginsCannotConnectOrEscapeCleanup() {
        val factory = CountDownLatch(1)
        val release = CountDownLatch(1)
        val socket = Socket()
        val transport = PrinterTransport { factory.countDown(); await(release); socket }
        try {
            val connection = transport.connect("A")
            await(factory)
            val close = transport.close()
            failure(transport.connect("B"), "busy")
            release.countDown()
            failure(connection, "timeout")
            done(close)
            assertEquals(listOf("close"), socket.events)
        } finally { release.countDown(); transport.shutdown() }
    }

    @Test fun failedCloseQuarantinesUntilExplicitCloseRecovery() {
        val socket = Socket()
        socket.onClose = { throw IOException("close failed") }
        val transport = PrinterTransport { socket }
        try {
            done(transport.connect("A"))
            failure(transport.close(), "close_failed")
            failure(transport.connect("B"), "busy")
            failure(transport.write(byteArrayOf(1)), "busy")
            socket.onClose = {}
            done(transport.close())
            done(transport.connect("B"))
        } finally { transport.shutdown() }
    }

    @Test fun connectionFailureRetainsSocketForCloseAndPermissionRevocationIsTyped() {
        val socket = Socket()
        socket.onConnect = { throw IOException("unreachable") }
        val transport = PrinterTransport { socket }
        try {
            failure(transport.connect("A"), "connection_failed")
            done(transport.close())
            assertEquals(listOf("connect", "close"), socket.events)
            socket.onConnect = {}
            socket.onWrite = { throw TransportFailure("permission_denied") }
            done(transport.connect("A"))
            failure(transport.write(byteArrayOf(1)), "permission_denied")
            done(transport.close())
        } finally { transport.shutdown() }
    }

    @Test fun securityExceptionIsNotLostAsGenericWriteFailure() {
        val socket = Socket()
        socket.onWrite = { throw SecurityException("permission revoked during write") }
        val transport = PrinterTransport { socket }
        try {
            done(transport.connect("A"))
            try { done(transport.write(byteArrayOf(1))); fail() }
            catch (error: ExecutionException) { assertTrue(error.cause is SecurityException) }
            done(transport.close())
        } finally { transport.shutdown() }
    }

    @Test fun destinationAtoBtoAAlwaysClosesPreviousSocket() {
        val sockets = mutableListOf<Pair<String, Socket>>()
        val transport = PrinterTransport { address ->
            Socket().also { sockets.add(address to it) }
        }
        try {
            for (address in listOf("A", "B", "A")) {
                done(transport.connect(address)); done(transport.write(byteArrayOf(65)))
            }
            done(transport.close())
            assertEquals(listOf("A", "B", "A"), sockets.map { it.first })
            sockets.forEach { assertEquals(listOf("connect", "write:1", "flush", "close"), it.second.events) }
        } finally { transport.shutdown() }
    }
}
