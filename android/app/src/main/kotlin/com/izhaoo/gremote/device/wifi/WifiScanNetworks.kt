package com.izhaoo.gremote.device.wifi

data class WifiScanNetwork(val ssid: String, val rssi: Int)

object WifiScanNetworks {
    fun select(networks: List<WifiScanNetwork>): List<WifiScanNetwork> = networks
        .filter { it.ssid.isNotEmpty() && it.ssid != "<unknown ssid>" &&
            it.ssid.toByteArray(Charsets.UTF_8).size <= 32 }
        .groupBy { it.ssid }
        .values.map { sameSsid -> sameSsid.maxBy { it.rssi } }
        .sortedWith(compareByDescending<WifiScanNetwork> { it.ssid.startsWith("RICOH") }
            .thenByDescending { it.rssi }.thenBy { it.ssid })
        .take(64)
}
