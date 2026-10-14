package com.izhaoo.gremote.device.http

import okhttp3.Call

/** Cancel transfers admitted after a disconnect, as well as active transfers. */
internal class PhotoTransferCalls {
    private val active = mutableSetOf<Call>()
    private var closed = false

    @Synchronized fun add(call: Call) {
        if (closed) call.cancel() else active.add(call)
    }

    @Synchronized fun remove(call: Call) {
        active.remove(call)
    }

    @Synchronized fun close() {
        closed = true
        active.forEach { it.cancel() }
        active.clear()
    }
}
