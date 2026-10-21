package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** WallpaperState の保存と読み出し (SharedPreferences "mrw_wallpaper")。 */
class WallpaperStateStoreTest {
    @Test
    fun `何も保存されていなければ 64 快適`() {
        val state = WallpaperStateStore.read(FakeSharedPreferences())
        assertEquals(WallpaperState(mri = 64, bandKey = null), state)
        assertEquals(WallpaperBand.COMFORTABLE, state.band)
    }

    @Test
    fun `MRI だけの古い保存データは値で区分を決める`() {
        // 1.3.0 (12) までは "mri" だけを保存していた
        val prefs = FakeSharedPreferences().apply { values["mri"] = 30 }
        val state = WallpaperStateStore.read(prefs)
        assertEquals(WallpaperState(mri = 30, bandKey = null), state)
        assertEquals(WallpaperBand.HOT, state.band)
    }

    @Test
    fun `保存した内容をそのまま読める`() {
        val prefs = FakeSharedPreferences()
        WallpaperStateStore.write(prefs, WallpaperState(mri = 74, bandKey = "comfortable"))
        assertEquals(mapOf("mri" to 74, "band" to "comfortable"), prefs.values)
        assertEquals(WallpaperState(mri = 74, bandKey = "comfortable"), WallpaperStateStore.read(prefs))
    }

    @Test
    fun `区分名の無い内容を保存すると前回の区分名は消える`() {
        val prefs = FakeSharedPreferences()
        WallpaperStateStore.write(prefs, WallpaperState(mri = 74, bandKey = "comfortable"))
        WallpaperStateStore.write(prefs, WallpaperState(mri = 30, bandKey = null))
        assertFalse(prefs.values.containsKey("band"))
        // 前回の「快適」が残らず、値 (暑い) で描く
        assertEquals(WallpaperBand.HOT, WallpaperStateStore.read(prefs).band)
    }

    @Test
    fun `範囲外の MRI は 0 から 100 に丸めて保存する`() {
        val prefs = FakeSharedPreferences()
        WallpaperStateStore.write(prefs, WallpaperState(mri = 130))
        assertEquals(100, WallpaperStateStore.read(prefs).mri)
    }

    @Test
    fun `データ削除で消すと既定 (MRI 64・区分名なし = 快適の配色) に戻る`() {
        val prefs = FakeSharedPreferences()
        WallpaperStateStore.write(prefs, WallpaperState(mri = 30, bandKey = "hot"))
        assertTrue(WallpaperStateStore.clear(prefs))
        assertFalse(prefs.values.containsKey("mri"))
        assertFalse(prefs.values.containsKey("band"))
        val state = WallpaperStateStore.read(prefs)
        assertEquals(WallpaperState(mri = 64, bandKey = null), state)
        assertEquals(WallpaperBand.COMFORTABLE, state.band)
        assertEquals(WallpaperPalette.forBand(WallpaperBand.COMFORTABLE), WallpaperPalette.forBand(state.band))
    }

    @Test
    fun `色の状態を消しても重ね描きの保存には触れない (重ね描きは別に消す)`() {
        val prefs = FakeSharedPreferences().apply {
            values["overlay_version"] = 3L
            values["overlay_serial"] = 3L
        }
        WallpaperStateStore.write(prefs, WallpaperState(mri = 74, bandKey = "comfortable"))
        WallpaperStateStore.clear(prefs)
        assertEquals(mapOf("overlay_version" to 3L, "overlay_serial" to 3L), prefs.values)
    }

    @Test
    fun `何も保存されていなくても消せる`() {
        val prefs = FakeSharedPreferences()
        assertTrue(WallpaperStateStore.clear(prefs))
        assertEquals(WallpaperState(mri = 64, bandKey = null), WallpaperStateStore.read(prefs))
    }

    @Test
    fun `消した後に書けば また読める (アプリが MRI を計算し直したとき)`() {
        val prefs = FakeSharedPreferences()
        WallpaperStateStore.write(prefs, WallpaperState(mri = 30, bandKey = "hot"))
        WallpaperStateStore.clear(prefs)
        WallpaperStateStore.write(prefs, WallpaperState(mri = 85, bandKey = "cool"))
        assertEquals(WallpaperBand.COOL, WallpaperStateStore.read(prefs).band)
    }
}
