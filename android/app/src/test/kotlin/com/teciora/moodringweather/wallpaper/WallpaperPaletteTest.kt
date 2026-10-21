package com.teciora.moodringweather.wallpaper

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** 区分 → 配色の表 (docs/design-wallpaper-palette.md §0・§3)。 */
class WallpaperPaletteTest {
    private fun hex(color: Int) = String.format("#%08X", color)

    private data class Expected(
        val top: String,
        val middle: String,
        val bottom: String,
        val glowCenter: String,
        /** 画面でいちばん明るい点 (光の中心) の色。設計書 §3.3・実機手順書 D-13。 */
        val brightest: String,
    )

    private val table = mapOf(
        WallpaperBand.COOL to
            Expected("#FF1C3855", "#FF132437", "#FF0D141B", "#6658A0EE", "#305986"),
        WallpaperBand.COMFORTABLE to
            Expected("#FF174734", "#FF122E22", "#FF0F1914", "#6646C795", "#287053"),
        WallpaperBand.WARM to
            Expected("#FF553D18", "#FF382912", "#FF1E1810", "#66EBAE4A", "#856229"),
        WallpaperBand.HOT to
            Expected("#FF56291D", "#FF381B14", "#FF1C110E", "#66F0795A", "#874332"),
        WallpaperBand.HOT_ALERT to
            Expected("#FF762115", "#FF57180F", "#FF3A130C", "#B3E5533D", "#BD4230"),
    )

    @Test
    fun `5 区分すべてに設計書どおりの配色がある`() {
        assertEquals(WallpaperBand.entries.toSet(), table.keys)
        for ((band, e) in table) {
            val p = WallpaperPalette.forBand(band)
            assertEquals("$band top", e.top, hex(p.top))
            assertEquals("$band middle", e.middle, hex(p.middle))
            assertEquals("$band bottom", e.bottom, hex(p.bottom))
            assertEquals("$band glowCenter", e.glowCenter, hex(p.glowCenter))
            assertEquals(
                "$band gradient",
                listOf(e.top, e.middle, e.bottom),
                p.gradient.map { hex(it) },
            )
        }
    }

    @Test
    fun `光の色はアプリの帯色トークン MrwTokens dark と同じ`() {
        val tokens = mapOf(
            WallpaperBand.COOL to 0x58A0EE, // stateCool
            WallpaperBand.COMFORTABLE to 0x46C795, // stateComfortable
            WallpaperBand.WARM to 0xEBAE4A, // stateWarm
            WallpaperBand.HOT to 0xF0795A, // stateHot
            WallpaperBand.HOT_ALERT to 0xE5533D, // stateDanger
        )
        for ((band, rgb) in tokens) {
            assertEquals("$band", rgb, WallpaperPalette.forBand(band).glowCenter and 0xFFFFFF)
        }
    }

    @Test
    fun `地は不透明で 光の中心は 40 パーセント とても暑いだけ 70 パーセント`() {
        for (band in WallpaperBand.entries) {
            val p = WallpaperPalette.forBand(band)
            for (c in p.gradient) assertEquals("$band ${hex(c)}", 0xFF, c ushr 24)
            val expectedAlpha = if (band == WallpaperBand.HOT_ALERT) 0xB3 else 0x66
            assertEquals("$band", expectedAlpha, p.glowCenter ushr 24)
        }
    }

    @Test
    fun `光の外周は中心と同じ色のアルファ 0`() {
        for (band in WallpaperBand.entries) {
            val p = WallpaperPalette.forBand(band)
            assertEquals("$band", 0, p.glowEdge ushr 24)
            assertEquals("$band", p.glowCenter and 0xFFFFFF, p.glowEdge)
        }
    }

    @Test
    fun `画面でいちばん明るい点は設計書の値で 白文字は 4_5 対 1 以上`() {
        // MoodRingWallpaperService.drawWallpaper と同じ形を 1080×2400 で 4px おきに計算する
        // (設計書 §3.2)。光の中心 (540, 840) は計算する点に含まれる。
        val w = 1080.0
        val h = 2400.0
        for ((band, e) in table) {
            val p = WallpaperPalette.forBand(band)
            var brightest = doubleArrayOf(0.0, 0.0, 0.0)
            var maxLuminance = -1.0
            var y = 0.0
            while (y <= h) {
                var x = 0.0
                while (x <= w) {
                    val rgb = composite(p, x, y, w, h)
                    val lum = relativeLuminance(rgb)
                    if (lum > maxLuminance) {
                        maxLuminance = lum
                        brightest = rgb
                    }
                    x += 4.0
                }
                y += 4.0
            }
            val expected = rgbOf(e.brightest)
            for (i in 0..2) {
                assertTrue(
                    "$band 最も明るい点 ${brightest.toList()} と設計書 ${e.brightest}",
                    abs(brightest[i] - expected[i]) <= 1.0,
                )
            }
            val contrast = 1.05 / (maxLuminance + 0.05)
            assertTrue("$band 白文字のコントラスト $contrast", contrast >= 4.5)
        }
    }

    /** (x, y) の画素 (0–255 の RGB)。地の上に光を重ねる (SRC_OVER)。 */
    private fun composite(p: WallpaperPalette, x: Double, y: Double, w: Double, h: Double): DoubleArray {
        val t = y / h
        val ground = if (t <= 0.5) {
            lerp(channels(p.top), channels(p.middle), t / 0.5)
        } else {
            lerp(channels(p.middle), channels(p.bottom), (t - 0.5) / 0.5)
        }
        val radius = max(w, h) * 0.5
        val distance = min(hypot(x - w * 0.5, y - h * 0.35) / radius, 1.0)
        val alpha = (p.glowCenter ushr 24) / 255.0 * (1.0 - distance)
        val glow = channels(p.glowCenter)
        return DoubleArray(3) { i -> glow[i] * alpha + ground[i] * (1.0 - alpha) }
    }

    private fun channels(color: Int) = doubleArrayOf(
        ((color shr 16) and 0xFF).toDouble(),
        ((color shr 8) and 0xFF).toDouble(),
        (color and 0xFF).toDouble(),
    )

    private fun lerp(a: DoubleArray, b: DoubleArray, t: Double) =
        DoubleArray(3) { i -> a[i] + (b[i] - a[i]) * t }

    private fun rgbOf(hex: String): DoubleArray = channels(hex.removePrefix("#").toInt(16))

    /** WCAG 2.x の相対輝度 (8 bit に丸めた sRGB から)。 */
    private fun relativeLuminance(rgb: DoubleArray): Double {
        fun linear(c: Double): Double {
            val s = c.roundToInt() / 255.0
            return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
    }
}
