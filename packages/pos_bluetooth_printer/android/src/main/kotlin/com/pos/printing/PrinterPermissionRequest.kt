package com.pos.printing

import java.util.concurrent.CompletableFuture

/** A deadline cannot dismiss the Android dialog. Keep the channel future
 * pending until its callback or Activity/engine detachment actually finishes it. */
internal class PrinterPermissionRequest {
    val future = CompletableFuture<String>()
    private var expired = false

    fun expire() { expired = true }

    fun finish(status: String) {
        if (expired) future.completeExceptionally(TransportFailure("timeout"))
        else future.complete(status)
    }
}
