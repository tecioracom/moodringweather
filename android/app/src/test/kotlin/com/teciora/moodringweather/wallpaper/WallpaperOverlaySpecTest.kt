package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** 重ね描きの切り替え (新しい / 古い)・置く位置・引数の読み取り。 */
class WallpaperOverlaySpecTest {
    private val asOf = 1_759_212_000_000L // 2026-09-30 15:00 JST
    private val hour = 60 * 60 * 1000L
    private val minute = 60 * 1000L
    private val spec = WallpaperOverlaySpec(asOfMillis = asOf, pixelRatio = 3f)

    @Test
    fun `データの時刻から 3 時間までは新しい表示 超えたら古い表示`() {
        assertEquals(OverlayVariant.FRESH, spec.variantAt(asOf))
        assertEquals(OverlayVariant.FRESH, spec.variantAt(asOf + 2 * hour + 59 * minute))
        assertEquals(OverlayVariant.FRESH, spec.variantAt(asOf + 3 * hour))
        assertEquals(OverlayVariant.STALE, spec.variantAt(asOf + 3 * hour + 1))
        assertEquals(OverlayVariant.STALE, spec.variantAt(asOf + 48 * hour))
    }

    @Test
    fun `時計が 15 分以上戻ったら古い表示`() {
        assertEquals(OverlayVariant.FRESH, spec.variantAt(asOf - 14 * minute - 59_000L))
        assertEquals(OverlayVariant.STALE, spec.variantAt(asOf - 15 * minute))
        assertEquals(OverlayVariant.STALE, spec.variantAt(asOf - 24 * hour))
    }

    @Test
    fun `古い表示に変わるまでの時間 すでに古ければ null`() {
        assertEquals(3 * hour + 1, spec.millisUntilStale(asOf))
        assertEquals(hour + 1, spec.millisUntilStale(asOf + 2 * hour))
        assertEquals(1L, spec.millisUntilStale(asOf + 3 * hour))
        assertNull(spec.millisUntilStale(asOf + 3 * hour + 1))
        assertNull(spec.millisUntilStale(asOf - 20 * minute))
        // 変わる時刻に描き直すと古い表示になる
        val now = asOf + 90 * minute
        assertEquals(OverlayVariant.STALE, spec.variantAt(now + spec.millisUntilStale(now)!!))
    }

    @Test
    fun `基準点を右端から 24dp ステータスバーの下 16dp に置く`() {
        // 1080px 幅・密度 3 の端末 (360dp)。ビットマップも 3 倍で描いた (余白 8dp = 24px)。
        val placement = spec.place(
            surfaceWidthPx = 1080,
            statusBarBottomPx = 72f,
            density = 3f,
            bitmapWidthPx = 300,
        )
        assertEquals(1f, placement.scale, 0f)
        // 基準点 (ビットマップの幅 − 24px, 24px) が画面の (1080 − 72, 72 + 48) に来る
        assertEquals(1080f - 72f, placement.left + (300 - 24), 0.001f)
        assertEquals(72f + 48f, placement.top + 24, 0.001f)
    }

    @Test
    fun `描いた解像度と端末の密度が違えば拡大縮小する`() {
        val placement = spec.copy(pixelRatio = 2f).place(
            surfaceWidthPx = 1080,
            statusBarBottomPx = 72f,
            density = 3f,
            bitmapWidthPx = 200,
        )
        assertEquals(1.5f, placement.scale, 0f)
        // 余白は 8dp × 2 = 16px。倍率 1.5 で基準点が (1080 − 72, 72 + 48) に来る
        assertEquals(1080f - 72f, placement.left + (200 - 16) * 1.5f, 0.001f)
        assertEquals(72f + 48f, placement.top + 16 * 1.5f, 0.001f)
    }

    @Test
    fun `画面の幅に収まらないときは縮める`() {
        // 中身 1500px (余白を除く) を 1080px の画面に。左右に 24dp (72px) を残す。
        val placement = spec.place(
            surfaceWidthPx = 1080,
            statusBarBottomPx = 72f,
            density = 3f,
            bitmapWidthPx = 1500 + 48,
        )
        assertEquals((1080f - 144f) / 1500f, placement.scale, 0.0001f)
        val contentLeft = placement.left + 24 * placement.scale
        assertEquals(72f, contentLeft, 0.01f)
    }

    @Test
    fun `引数を読む`() {
        val fresh = byteArrayOf(1, 2, 3)
        val stale = byteArrayOf(4, 5)
        val update = WallpaperOverlaySpec.fromChannelArguments(
            mapOf(
                "asOf" to asOf,
                "fresh" to fresh,
                "stale" to stale,
                "pixelRatio" to 2.75,
                "paddingDp" to 8.0,
                "rightDp" to 24.0,
                "topGapDp" to 16.0,
                "staleAfterMinutes" to 180,
                "futureToleranceMinutes" to 15,
                "somethingNew" to "ignored",
            ),
        )
        assertNotNull(update)
        assertEquals(
            WallpaperOverlaySpec(
                asOfMillis = asOf,
                pixelRatio = 2.75f,
                paddingDp = 8f,
                rightDp = 24f,
                topGapDp = 16f,
                staleAfterMillis = 3 * hour,
                futureToleranceMillis = 15 * minute,
            ),
            update!!.spec,
        )
        assertArrayEquals(fresh, update.freshPng)
        assertArrayEquals(stale, update.stalePng)
    }

    @Test
    fun `配置の数値が無ければ既定値 時刻は Int でも読む`() {
        val update = WallpaperOverlaySpec.fromChannelArguments(
            mapOf(
                "asOf" to 1_000,
                "fresh" to byteArrayOf(1),
                "stale" to byteArrayOf(2),
                "pixelRatio" to 3,
            ),
        )
        assertEquals(WallpaperOverlaySpec(asOfMillis = 1_000L, pixelRatio = 3f), update?.spec)
    }

    @Test
    fun `時刻・PNG・解像度が無い 壊れているときは null`() {
        val ok = mapOf(
            "asOf" to asOf,
            "fresh" to byteArrayOf(1),
            "stale" to byteArrayOf(2),
            "pixelRatio" to 3.0,
        )
        assertNotNull(WallpaperOverlaySpec.fromChannelArguments(ok))
        assertNull(WallpaperOverlaySpec.fromChannelArguments(null))
        assertNull(WallpaperOverlaySpec.fromChannelArguments("x"))
        for (key in ok.keys) {
            assertNull(key, WallpaperOverlaySpec.fromChannelArguments(ok - key))
        }
        assertNull(WallpaperOverlaySpec.fromChannelArguments(ok + ("fresh" to byteArrayOf())))
        assertNull(WallpaperOverlaySpec.fromChannelArguments(ok + ("pixelRatio" to 0.0)))
        assertNull(WallpaperOverlaySpec.fromChannelArguments(ok + ("pixelRatio" to Double.NaN)))
        assertNull(WallpaperOverlaySpec.fromChannelArguments(ok + ("asOf" to "now")))
    }
}
