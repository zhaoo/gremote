package com.izhaoo.gremote.device.wifi

import kotlinx.coroutines.CompletableDeferred

/** State for one system Wi-Fi request, including callbacks arriving after unregister. */
internal class NetworkRequestLifecycle<N> {
    class Attempt<N> {
        val result = CompletableDeferred<N>()
    }

    private val lock = Any()
    private var current: Attempt<N>? = null
    private var network: N? = null

    fun begin(): Attempt<N> = synchronized(lock) {
        current?.result?.cancel()
        network = null
        Attempt<N>().also { current = it }
    }

    fun available(attempt: Attempt<N>, value: N, notify: () -> Unit): Boolean =
        synchronized(lock) {
            if (current !== attempt || attempt.result.isCompleted) {
                return@synchronized false
            }
            network = value
            notify()
            attempt.result.complete(value)
        }

    fun unavailable(attempt: Attempt<N>, error: Throwable): Boolean = synchronized(lock) {
        current === attempt && attempt.result.completeExceptionally(error)
    }

    fun lost(attempt: Attempt<N>, value: N, notify: () -> Unit): Boolean =
        synchronized(lock) {
            if (current !== attempt || network != value) return@synchronized false
            network = null
            notify()
            true
        }

    fun end(attempt: Attempt<N>): Boolean = synchronized(lock) {
        if (current !== attempt) return@synchronized false
        current = null
        network = null
        attempt.result.cancel()
        true
    }
}
