package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * アプリからライブ壁紙を設定する手順 (設定 › 一般「ライブ壁紙を設定」。1.3.0 (14))。
 * Intent の組み立てと起動は MainActivity。ここでは試す順・フォールバック・判定を見る。
 */
class LiveWallpaperPickerTest {
    private val own = "com.teciora.moodringweather"
    private val ownClass = "com.teciora.moodringweather.wallpaper.MoodRingWallpaperService"

    @Test
    fun `試す順は プレビュー (この壁紙を指定) → ライブ壁紙の一覧`() {
        assertEquals(
            listOf(
                LiveWallpaperPicker.Attempt(
                    "android.service.wallpaper.CHANGE_LIVE_WALLPAPER",
                    withComponent = true,
                ),
                LiveWallpaperPicker.Attempt(
                    "android.service.wallpaper.LIVE_WALLPAPER_CHOOSER",
                    withComponent = false,
                ),
            ),
            LiveWallpaperPicker.ATTEMPTS,
        )
    }

    @Test
    fun `プレビューが開ければ一覧は試さない`() {
        val tried = mutableListOf<LiveWallpaperPicker.Attempt>()
        val opened = LiveWallpaperPicker.open { tried.add(it) }
        assertTrue(opened)
        assertEquals(listOf(LiveWallpaperPicker.ATTEMPTS[0]), tried)
    }

    @Test
    fun `プレビューが開けなければ一覧を開く`() {
        val tried = mutableListOf<LiveWallpaperPicker.Attempt>()
        val opened = LiveWallpaperPicker.open {
            tried.add(it)
            if (it.withComponent) throw IllegalStateException("no preview activity")
        }
        assertTrue(opened)
        assertEquals(LiveWallpaperPicker.ATTEMPTS, tried)
    }

    @Test
    fun `どちらも開けなければ false で、例外は外へ出さない`() {
        val tried = mutableListOf<LiveWallpaperPicker.Attempt>()
        val opened = LiveWallpaperPicker.open {
            tried.add(it)
            if (it.withComponent) throw IllegalStateException("not found")
            throw SecurityException("not allowed")
        }
        assertFalse(opened)
        assertEquals(LiveWallpaperPicker.ATTEMPTS, tried)
    }

    @Test
    fun `試すものが無ければ false`() {
        assertFalse(LiveWallpaperPicker.open(emptyList()) { })
    }

    @Test
    fun `今の壁紙がこのアプリのライブ壁紙なら true`() {
        assertTrue(LiveWallpaperPicker.isOwnWallpaper(own, ownClass, own, ownClass))
    }

    @Test
    fun `静止画の壁紙 (ライブ壁紙の情報が無い) は false`() {
        assertFalse(LiveWallpaperPicker.isOwnWallpaper(null, null, own, ownClass))
    }

    @Test
    fun `ほかのライブ壁紙・同じパッケージの別のクラスは false`() {
        assertFalse(
            LiveWallpaperPicker.isOwnWallpaper(
                "com.android.wallpaper.livepicker",
                "com.android.wallpaper.SomeLiveWallpaper",
                own,
                ownClass,
            ),
        )
        assertFalse(
            LiveWallpaperPicker.isOwnWallpaper(own, "$own.wallpaper.Other", own, ownClass),
        )
        assertFalse(
            LiveWallpaperPicker.isOwnWallpaper("$own.debug", ownClass, own, ownClass),
        )
    }
}
