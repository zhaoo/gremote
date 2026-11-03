package com.izhaoo.gremote.imaging

import org.junit.Assert.*
import org.junit.Test

class GpuSurfaceLifecycleTest {
    @Test fun recreation_discards_obsolete_queued_attach_and_detach() {
        val queue = mutableListOf<() -> Unit>()
        val events = mutableListOf<String>()
        val surface = GpuSurfaceLifecycle<String>(post = { queue.add(it) },
            attach = { events.add("attach:$it") }, detach = { events.add("detach") },
            release = { events.add("release") })
        surface.created("old"); surface.destroyed(); surface.created("new")
        while (queue.isNotEmpty()) queue.removeAt(0).invoke()
        assertEquals(listOf("attach:new"), events)
        surface.destroyed(); queue.removeAt(0).invoke()
        assertEquals(listOf("attach:new", "detach"), events)
    }
    @Test fun close_revokes_every_queued_surface_and_releases_once_on_owner_queue() {
        val queue = mutableListOf<() -> Unit>()
        val events = mutableListOf<String>()
        val surface = GpuSurfaceLifecycle<String>(post = { queue.add(it) },
            attach = { events.add("attach:$it") }, detach = { events.add("detach") },
            release = { events.add("release") })
        surface.created("old"); surface.close(); surface.close(); surface.created("late")
        assertTrue(events.isEmpty())
        while (queue.isNotEmpty()) queue.removeAt(0).invoke()
        assertEquals(listOf("detach", "release"), events)
    }
}
