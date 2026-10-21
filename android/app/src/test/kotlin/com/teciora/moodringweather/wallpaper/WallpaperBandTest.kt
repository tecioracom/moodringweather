package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 区分の判定。境界の表は test/unit/wallpaper_bridge_test.dart (Dart の MriBand.fromValue) と同じ。
 * 区分を決める正本は Dart で、Kotlin の fromMri は区分名の無い古い保存データ用の写し。
 */
class WallpaperBandTest {
    @Test
    fun `区分名は Dart の MriBand の名前と同じ並び`() {
        assertEquals(
            listOf("cool", "comfortable", "warm", "hot", "hotAlert"),
            WallpaperBand.entries.map { it.key },
        )
    }

    @Test
    fun `区分名から区分を引ける`() {
        for (band in WallpaperBand.entries) {
            assertEquals(band, WallpaperBand.fromKey(band.key))
        }
    }

    @Test
    fun `無い名前と知らない名前は null`() {
        for (key in listOf(null, "", "optimal", "COOL", "Cool", "hot_alert", "hotalert", " cool")) {
            assertNull("key=$key", WallpaperBand.fromKey(key))
        }
    }

    @Test
    fun `MRI の境界は Dart と同じ 80 60 40 20 で下端を含む`() {
        val table = listOf(
            0 to WallpaperBand.HOT_ALERT,
            19 to WallpaperBand.HOT_ALERT,
            20 to WallpaperBand.HOT,
            39 to WallpaperBand.HOT,
            40 to WallpaperBand.WARM,
            59 to WallpaperBand.WARM,
            60 to WallpaperBand.COMFORTABLE,
            64 to WallpaperBand.COMFORTABLE,
            79 to WallpaperBand.COMFORTABLE,
            80 to WallpaperBand.COOL,
            100 to WallpaperBand.COOL,
        )
        for ((mri, expected) in table) {
            assertEquals("mri=$mri", expected, WallpaperBand.fromMri(mri))
        }
    }

    @Test
    fun `範囲外の MRI でも落ちずに端の区分`() {
        assertEquals(WallpaperBand.HOT_ALERT, WallpaperBand.fromMri(-5))
        assertEquals(WallpaperBand.COOL, WallpaperBand.fromMri(130))
    }
}
