package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** 重ね描きの保存と読み出し (PNG 2 枚 + SharedPreferences)。 */
class WallpaperOverlayStoreTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val prefs = FakeSharedPreferences()
    private val dir: File get() = File(folder.root, WallpaperOverlayStore.DIRECTORY)

    private fun update(asOf: Long, fresh: ByteArray, stale: ByteArray) = WallpaperOverlayUpdate(
        spec = WallpaperOverlaySpec(asOfMillis = asOf, pixelRatio = 2.75f, rightDp = 20f),
        freshPng = fresh,
        stalePng = stale,
    )

    @Test
    fun `何も保存されていなければ null`() {
        assertNull(WallpaperOverlayStore.read(prefs, dir))
    }

    @Test
    fun `保存した内容をそのまま読める`() {
        WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1, 2), byteArrayOf(3)))
        val stored = WallpaperOverlayStore.read(prefs, dir)
        assertNotNull(stored)
        assertEquals(
            WallpaperOverlaySpec(asOfMillis = 1_000L, pixelRatio = 2.75f, rightDp = 20f),
            stored!!.spec,
        )
        assertArrayEquals(byteArrayOf(1, 2), stored.file(OverlayVariant.FRESH).readBytes())
        assertArrayEquals(byteArrayOf(3), stored.file(OverlayVariant.STALE).readBytes())
    }

    @Test
    fun `書き直すと版が変わり 古い版の PNG と一時ファイルは残らない`() {
        val first = WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1), byteArrayOf(2)))
        val second = WallpaperOverlayStore.write(prefs, dir, update(2_000L, byteArrayOf(3), byteArrayOf(4)))
        assertNotEquals(first, second)
        val stored = WallpaperOverlayStore.read(prefs, dir)!!
        assertEquals(second, stored.version)
        assertEquals(2_000L, stored.spec.asOfMillis)
        assertArrayEquals(byteArrayOf(3), stored.fresh.readBytes())
        assertEquals(
            setOf(stored.fresh.name, stored.stale.name),
            dir.listFiles()!!.map { it.name }.toSet(),
        )
    }

    @Test
    fun `消すと読めなくなり PNG も消える`() {
        WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1), byteArrayOf(2)))
        WallpaperOverlayStore.clear(prefs, dir)
        assertNull(WallpaperOverlayStore.read(prefs, dir))
        assertTrue(dir.listFiles().isNullOrEmpty())
    }

    @Test
    fun `消した後に書いても版の番号は前と重ならない`() {
        // エンジンが持っている古いビットマップを、同じ番号の新しい組と取り違えないため
        val first = WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1), byteArrayOf(2)))
        WallpaperOverlayStore.clear(prefs, dir)
        val second = WallpaperOverlayStore.write(prefs, dir, update(2_000L, byteArrayOf(3), byteArrayOf(4)))
        assertTrue(second > first)
    }

    @Test
    fun `データ削除で消すと 重ね描きの設定と PNG がすべて消え 色の状態には触れない`() {
        prefs.values["mri"] = 30
        prefs.values["band"] = "hot"
        WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1), byteArrayOf(2)))
        WallpaperOverlayStore.clear(prefs, dir)
        assertNull(WallpaperOverlayStore.read(prefs, dir))
        assertTrue(dir.listFiles().isNullOrEmpty())
        // 残るのは色の状態 (別に消す) と版の番号だけ
        assertEquals(setOf("mri", "band", "overlay_serial"), prefs.values.keys)
    }

    @Test
    fun `消したことが無くても 何も無いところを消せる`() {
        WallpaperOverlayStore.clear(prefs, dir)
        assertNull(WallpaperOverlayStore.read(prefs, dir))
    }

    @Test
    fun `PNG が欠けていれば null`() {
        WallpaperOverlayStore.write(prefs, dir, update(1_000L, byteArrayOf(1), byteArrayOf(2)))
        WallpaperOverlayStore.read(prefs, dir)!!.stale.delete()
        assertNull(WallpaperOverlayStore.read(prefs, dir))
    }
}
