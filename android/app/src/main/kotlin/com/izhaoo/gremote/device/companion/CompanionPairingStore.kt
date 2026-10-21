package com.izhaoo.gremote.device.companion

import android.security.keystore.KeyProperties
import android.security.keystore.KeyProtection
import java.security.KeyStore
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Imported keys persist only as AndroidKeyStore entries; no key export API. */
class CompanionPairingStore {
    private fun alias(instanceId: String): String {
        require(instanceId.matches(Regex("[a-f0-9]{32}"))) { "Invalid companion identity" }
        return "gremote.companion.$instanceId"
    }
    private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    fun save(instanceId: String, key: ByteArray) {
        require(key.size == 32) { "Invalid companion key length" }
        try {
            store().setEntry(alias(instanceId), KeyStore.SecretKeyEntry(SecretKeySpec(key, "HmacSHA256")),
                KeyProtection.Builder(KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setDigests(KeyProperties.DIGEST_SHA256).build())
        } finally { key.fill(0) }
    }
    fun remove(instanceId: String) { store().deleteEntry(alias(instanceId)) }
    fun sign(instanceId: String, canonical: ByteArray): ByteArray {
        require(canonical.size <= 1024) { "Canonical request exceeds limit" }
        val key = store().getKey(alias(instanceId), null) ?: throw IllegalStateException("Companion pairing missing")
        return Mac.getInstance("HmacSHA256").apply { init(key) }.doFinal(canonical)
    }
}
