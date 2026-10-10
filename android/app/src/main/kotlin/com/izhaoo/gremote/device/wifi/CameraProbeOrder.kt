package com.izhaoo.gremote.device.wifi

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

fun interface CameraProbe {
    suspend fun probe(baseUrl: String): CameraProbeResult
}

sealed interface CameraProbeResult {
    object ValidJson : CameraProbeResult
    object NotFound : CameraProbeResult
    object ConnectionFailure : CameraProbeResult
    object InvalidResponse : CameraProbeResult
}

class CameraProbeOrder(
    private val probe: CameraProbe,
    private val candidates: List<String> = listOf(
        "http://192.168.0.1",
        "http://192.168.1.1",
    ),
) {
    suspend fun findBaseUrl(): String {
        for (candidate in candidates) {
            currentCoroutineContext().ensureActive()
            when (probe.probe(candidate)) {
                CameraProbeResult.ValidJson -> return candidate
                CameraProbeResult.ConnectionFailure,
                CameraProbeResult.NotFound,
                -> continue
                CameraProbeResult.InvalidResponse -> throw CameraNetworkException(
                    code = "cameraProbeInvalid",
                    message = "Camera ping returned an invalid response",
                )
            }
        }
        throw CameraNetworkException(
            code = "cameraProbeFailed",
            message = "No supported camera endpoint responded",
        )
    }
}
