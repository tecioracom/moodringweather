package com.teciora.moodringweather.wallpaper

/**
 * ライブ壁紙の 1 区分の配色 (docs/design-wallpaper-palette.md §0。2026-09-30 ユーザー決裁)。
 *
 * - 地: 縦のグラデーション。上 (y=0) → 中 (y=0.5h) → 下 (y=h) を均等に置く。
 * - 光: 中心 (0.5w, 0.35h)・半径 max(w, h) × 0.5 の放射状。中心の不透明度から外周で 0。
 *
 * 光の色はアプリの帯色トークン (lib/presentation/theme/mrw_tokens.dart の MrwTokens.dark、
 * stateCool〜stateDanger) そのもの。地はその色相のまま暗くした色 (設計書 §2.1 の式)。
 * 帯色トークンを変えたときは同じ式で作り直す。白文字 (ランチャーのラベル・日付・
 * ステータスバー) は画面のどこでも 4.5:1 以上 (設計書 §3)。
 * 端末のライト / ダーク設定では変えない (1 区分 1 配色。壁紙は常に暗い面)。
 *
 * 色は android.graphics.Color と同じ並びの ARGB の Int。android.graphics に依存しないので、
 * 表は JVM のユニットテスト (src/test) で確かめる。
 */
data class WallpaperPalette(
    /** 地・上 (y=0)。 */
    val top: Int,
    /** 地・中 (y=0.5h)。 */
    val middle: Int,
    /** 地・下 (y=h)。 */
    val bottom: Int,
    /** 光の中心 (アルファ込み)。 */
    val glowCenter: Int,
) {
    /** LinearGradient に渡す地の 3 色 (上 → 中 → 下)。 */
    val gradient: IntArray
        get() = intArrayOf(top, middle, bottom)

    /**
     * 光の外周 = 中心と同じ色のアルファ 0。黒の透明 (Color.TRANSPARENT) にすると、
     * 補間のしかたによっては外周に暗いにじみが出る。
     */
    val glowEdge: Int
        get() = glowCenter and 0x00FFFFFF

    companion object {
        /** 区分 → 配色。OPTIMAL は快適と同じ (区分としては comfortable で届く)。 */
        fun forBand(band: WallpaperBand): WallpaperPalette = when (band) {
            // 涼しい 80–100。光 = stateCool #58A0EE の 40%
            WallpaperBand.COOL -> WallpaperPalette(
                top = argb(0xFF1C3855),
                middle = argb(0xFF132437),
                bottom = argb(0xFF0D141B),
                glowCenter = argb(0x6658A0EE),
            )
            // 快適 60–79。光 = stateComfortable #46C795 の 40%
            WallpaperBand.COMFORTABLE -> WallpaperPalette(
                top = argb(0xFF174734),
                middle = argb(0xFF122E22),
                bottom = argb(0xFF0F1914),
                glowCenter = argb(0x6646C795),
            )
            // やや暑い 40–59。光 = stateWarm #EBAE4A の 40%
            WallpaperBand.WARM -> WallpaperPalette(
                top = argb(0xFF553D18),
                middle = argb(0xFF382912),
                bottom = argb(0xFF1E1810),
                glowCenter = argb(0x66EBAE4A),
            )
            // 暑い 20–39。光 = stateHot #F0795A の 40%
            WallpaperBand.HOT -> WallpaperPalette(
                top = argb(0xFF56291D),
                middle = argb(0xFF381B14),
                bottom = argb(0xFF1C110E),
                glowCenter = argb(0x66F0795A),
            )
            // とても暑い 0–19。警告として地の彩度と光を強める。光 = stateDanger #E5533D の 70%
            WallpaperBand.HOT_ALERT -> WallpaperPalette(
                top = argb(0xFF762115),
                middle = argb(0xFF57180F),
                bottom = argb(0xFF3A130C),
                glowCenter = argb(0xB3E5533D),
            )
        }

        /** 0xAARRGGBB (Long のリテラル) → ARGB の Int。 */
        private fun argb(value: Long): Int = value.toInt()
    }
}
