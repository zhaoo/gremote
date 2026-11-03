package com.izhaoo.gremote.imaging

import org.junit.Assert.*
import org.junit.Test

class GpuFrameSchedulerTest {
    @Test fun queued_touches_keep_only_the_newest_pending_request() {
        val queue = mutableListOf<() -> Unit>()
        val rendered = mutableListOf<Int>()
        val frames = mutableListOf<Int>()
        val scheduler = GpuFrameScheduler<Int, Int>(
            post = { queue.add(it) }, render = { rendered.add(it); it },
            emit = { _, value -> frames.add(value) }, error = { _, e -> throw e })
        scheduler.submit(1, 10); scheduler.submit(2, 20); scheduler.submit(3, 30)
        assertEquals(1, queue.size)
        queue.removeAt(0).invoke()
        assertEquals(listOf(30), rendered)
        assertEquals(listOf(30), frames)
        assertFalse(scheduler.submit(2, 999))
    }

    @Test fun input_during_render_revokes_old_frame_and_renders_latest() {
        val queue = mutableListOf<() -> Unit>()
        val frames = mutableListOf<Int>()
        lateinit var scheduler: GpuFrameScheduler<Int, Int>
        scheduler = GpuFrameScheduler(post = { queue.add(it) }, render = {
            if (it == 1) { scheduler.submit(2, 2); scheduler.submit(3, 3) }
            it
        }, emit = { _, value -> frames.add(value) }, error = { _, e -> throw e })
        scheduler.submit(1, 1)
        queue.removeAt(0).invoke()
        assertEquals(listOf(3), frames)
        assertTrue(queue.isEmpty())
    }

    @Test fun cancel_revokes_late_errors_without_preventing_a_new_request() {
        val queue = mutableListOf<() -> Unit>()
        val frames = mutableListOf<Int>()
        val errors = mutableListOf<Throwable>()
        lateinit var scheduler: GpuFrameScheduler<Int, Int>
        scheduler = GpuFrameScheduler(post = { queue.add(it) }, render = {
            if (it == 1) { scheduler.invalidate(2); throw IllegalStateException("obsolete") }
            it
        }, emit = { _, value -> frames.add(value) }, error = { _, e -> errors.add(e) })
        scheduler.submit(1, 1); queue.removeAt(0).invoke()
        assertTrue(errors.isEmpty()); assertTrue(frames.isEmpty())
        scheduler.submit(3, 3); queue.removeAt(0).invoke()
        assertEquals(listOf(3), frames)
    }

    @Test fun close_during_render_drops_delivery_and_is_idempotent() {
        val queue = mutableListOf<() -> Unit>()
        val frames = mutableListOf<Int>()
        lateinit var scheduler: GpuFrameScheduler<Int, Int>
        scheduler = GpuFrameScheduler(post = { queue.add(it) }, render = {
            scheduler.close(); scheduler.close(); it
        }, emit = { _, value -> frames.add(value) }, error = { _, e -> throw e })
        scheduler.submit(1, 1); queue.removeAt(0).invoke()
        assertTrue(frames.isEmpty())
        assertFalse(scheduler.submit(2, 2))
    }
}
