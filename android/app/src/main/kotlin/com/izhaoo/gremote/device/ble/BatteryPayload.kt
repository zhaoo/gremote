package com.izhaoo.gremote.device.ble

data class BatteryPayload(val level: Int, val acPowered: Boolean) {
    companion object {
        fun parse(bytes: ByteArray): BatteryPayload {
            if (bytes.size !in 1..2) {
                throw RicohBleException("invalidPayload", "Battery payload length is ${bytes.size}")
            }
            val level = bytes[0].toUByte().toInt()
            val source = if (bytes.size == 2) bytes[1].toUByte().toInt() else 0
            if (level > 100 || source !in 0..1) {
                throw RicohBleException("invalidPayload", "Battery payload values are invalid")
            }
            return BatteryPayload(level, source == 1)
        }
    }
}
