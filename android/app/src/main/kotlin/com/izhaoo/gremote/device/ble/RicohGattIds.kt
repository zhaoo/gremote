package com.izhaoo.gremote.device.ble

import java.util.UUID

object RicohGattIds {
    val CAMERA_INFORMATION_SERVICE: UUID = uuid("9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1")
    val MODEL: UUID = uuid("35fe6272-6aa5-44d9-88e1-f09427f51a71")
    val FIRMWARE: UUID = uuid("b4eb8905-7411-40a6-a367-2834c2157ea7")

    val CAMERA_SERVICE: UUID = uuid("4b445988-caa0-4dd3-941d-37b4f52aca86")
    val CAMERA_POWER: UUID = uuid("b58ce84c-0666-4de9-bec8-2d27b27b3211")
    val BATTERY: UUID = uuid("875fc41d-4980-434c-a653-fd4a4d4410c4")

    val WLAN_SERVICE: UUID = uuid("f37f568f-9071-445d-a938-5441f2e82399")
    val NETWORK_TYPE: UUID = uuid("9111cdd0-9f01-45c4-a2d4-e09e8fb0424d")
    val SSID: UUID = uuid("90638e5a-e77d-409d-b550-78f7e1ca5ab4")
    val PASSPHRASE: UUID = uuid("0f38279c-fe9e-461b-8596-81287e8c9a81")

    val SHOOTING_SERVICE: UUID = uuid("9f00f387-8345-4bbc-8b92-b87b52e3091a")
    val OPERATION_REQUEST: UUID = uuid("559644b8-e0bc-4011-929b-5cf9199851e7")
    val CAPTURE_STATUS: UUID = uuid("b5589c08-b5fd-46f5-be7d-ab1b8c074caa")

    val CLIENT_CHARACTERISTIC_CONFIG: UUID =
        uuid("00002902-0000-1000-8000-00805f9b34fb")

    val SCAN_SERVICES = setOf(CAMERA_INFORMATION_SERVICE, CAMERA_SERVICE)

    private fun uuid(value: String): UUID = UUID.fromString(value)
}
