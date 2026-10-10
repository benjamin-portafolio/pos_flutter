package com.pos.printing

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.ExecutionException

class PrinterPermissionRequestTest {
    @Test fun deadlineKeepsFuturePendingUntilLateCallbackAndReportsTimeoutOnce() {
        val request = PrinterPermissionRequest()
        var completions = 0
        request.future.whenComplete { _, _ -> completions++ }
        request.expire()
        assertFalse(request.future.isDone)
        assertEquals(0, completions)
        request.finish("granted")
        try { request.future.get(); fail("Expected timeout") }
        catch (error: ExecutionException) {
            assertEquals("timeout", (error.cause as TransportFailure).code)
        }
        request.finish("denied")
        assertEquals(1, completions)
    }

    @Test fun callbackBeforeDeadlinePreservesPermissionResult() {
        for (status in listOf("granted", "denied", "permanently_denied")) {
            val request = PrinterPermissionRequest()
            request.finish(status)
            request.expire()
            assertEquals(status, request.future.get())
        }
    }

    @Test fun detachmentTerminatesExpiredRequestWithoutGrantingOrReplaying() {
        val request = PrinterPermissionRequest()
        request.expire()
        assertFalse(request.future.isDone)
        request.finish("denied") // Activity/engine detachment uses the same barrier.
        assertTrue(request.future.isCompletedExceptionally)
    }
}
