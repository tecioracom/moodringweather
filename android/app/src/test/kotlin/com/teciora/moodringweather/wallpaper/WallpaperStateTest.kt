package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** setMriState の引数 (Dart の WallpaperState.toChannelArguments) の読み取り。 */
class WallpaperStateTest {
    @Test
    fun `MRI と区分名を読む`() {
        val state = WallpaperState.fromChannelArguments(mapOf("mri" to 74, "band" to "comfortable"))
        assertEquals(WallpaperState(mri = 74, bandKey = "comfortable"), state)
        assertEquals(WallpaperBand.COMFORTABLE, state.band)
    }

    @Test
    fun `区分名があれば区分名で決める`() {
        // 区分の正本は Dart。値と区分名が食い違っても区分名に従う
        val state = WallpaperState.fromChannelArguments(mapOf("mri" to 30, "band" to "cool"))
        assertEquals(WallpaperBand.COOL, state.band)
    }

    @Test
    fun `区分名が無ければ従来どおり MRI の値で決める`() {
        val state = WallpaperState.fromChannelArguments(mapOf("mri" to 30))
        assertNull(state.bandKey)
        assertEquals(WallpaperBand.HOT, state.band)
    }

    @Test
    fun `知らない区分名は MRI の値で決める`() {
        for (band in listOf("optimal", "", "COOL")) {
            val state = WallpaperState.fromChannelArguments(mapOf("mri" to 85, "band" to band))
            assertEquals("band=$band", WallpaperBand.COOL, state.band)
        }
    }

    @Test
    fun `区分名が文字列でなければ区分名なし`() {
        val state = WallpaperState.fromChannelArguments(mapOf("mri" to 45, "band" to 3))
        assertNull(state.bandKey)
        assertEquals(WallpaperBand.WARM, state.band)
    }

    @Test
    fun `MRI が無い・引数が Map でないときは 64 快適`() {
        val expected = WallpaperState(mri = 64, bandKey = null)
        assertEquals(expected, WallpaperState.fromChannelArguments(null))
        assertEquals(expected, WallpaperState.fromChannelArguments(42))
        assertEquals(expected, WallpaperState.fromChannelArguments(emptyMap<String, Any>()))
        assertEquals(expected, WallpaperState.fromChannelArguments(mapOf("mri" to "74")))
        assertEquals(WallpaperBand.COMFORTABLE, WallpaperState.fromChannelArguments(null).band)
    }

    @Test
    fun `MRI は Long でも読み 0 から 100 に丸める`() {
        assertEquals(74, WallpaperState.fromChannelArguments(mapOf("mri" to 74L)).mri)
        assertEquals(100, WallpaperState.fromChannelArguments(mapOf("mri" to 130)).mri)
        assertEquals(0, WallpaperState.fromChannelArguments(mapOf("mri" to -5)).mri)
    }

    @Test
    fun `知らないキーは無視する 項目を足しても古い読み手が壊れない`() {
        val state = WallpaperState.fromChannelArguments(
            mapOf(
                "mri" to 74,
                "band" to "comfortable",
                "temperatureLabel" to "22°",
                "weatherKind" to "sunny",
                "updatedAt" to 1_759_212_000_000L,
            ),
        )
        assertEquals(WallpaperState(mri = 74, bandKey = "comfortable"), state)
    }
}
