package com.izhaoo.gremote.media
/** ICC, if present, remains authoritative in the native source normalizer. */
object SourceColorPolicy {
    fun isAdobeRgb(colorSpace: Int, interoperability: String?): Boolean =
        colorSpace == 2 || interoperability == "R03"
}
