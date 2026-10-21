package com.teciora.moodringweather.wallpaper

/**
 * ライブ壁紙の重ね描き (天気グリフ・気温・区分名 · 時刻) の設定と、どちらの表示を
 * どこに置くかの判定 (docs/design-wallpaper-weather-overlay.md §2・§3・§7、2026-09-30 決裁)。
 *
 * 文字とグリフは Flutter が 2 枚のビットマップ (新しい表示 / 古い表示) に描いて渡す
 * (lib/presentation/wallpaper/)。Kotlin が持つのは、置く位置と、時刻による 2 枚の
 * 切り替えだけ。配置の数値も Dart から届く (無ければ既定値)。android.* に依存しないので、
 * JVM のユニットテスト (src/test) で確かめる。
 */
enum class OverlayVariant { FRESH, STALE }

data class WallpaperOverlaySpec(
    /** データの時刻 (エポックミリ秒)。 */
    val asOfMillis: Long,
    /** ビットマップを描いた解像度 (1dp あたりの画素数)。 */
    val pixelRatio: Float,
    /** 基準点 (重ね描きの右上) の周りの余白 (dp)。基準点はビットマップの (幅 − 余白, 余白)。 */
    val paddingDp: Float = DEFAULT_PADDING_DP,
    /** 画面の右端から基準点まで (dp)。 */
    val rightDp: Float = DEFAULT_RIGHT_DP,
    /** ステータスバーの下端から基準点まで (dp)。 */
    val topGapDp: Float = DEFAULT_TOP_GAP_DP,
    /** データの時刻からこれを超えたら古い表示 (ミリ秒)。 */
    val staleAfterMillis: Long = DEFAULT_STALE_AFTER_MILLIS,
    /** データの時刻が端末の時計よりこれ以上先なら古い表示 (時計が戻ったとき。ミリ秒)。 */
    val futureToleranceMillis: Long = DEFAULT_FUTURE_TOLERANCE_MILLIS,
) {
    /** [nowMillis] に描く表示。 */
    fun variantAt(nowMillis: Long): OverlayVariant {
        val age = nowMillis - asOfMillis
        return if (age > staleAfterMillis || -age >= futureToleranceMillis) {
            OverlayVariant.STALE
        } else {
            OverlayVariant.FRESH
        }
    }

    /** 新しい表示から古い表示に変わるまで (ミリ秒)。すでに古い表示なら null。 */
    fun millisUntilStale(nowMillis: Long): Long? =
        if (variantAt(nowMillis) == OverlayVariant.STALE) {
            null
        } else {
            asOfMillis + staleAfterMillis + 1 - nowMillis
        }

    /**
     * ビットマップを置く位置と倍率。基準点を画面の (幅 − 右の余白, ステータスバーの下端 +
     * 上の間隔) に合わせる。解像度が端末の密度と違えば拡大縮小し、画面の幅に収まらない
     * ときは (左右に右の余白を残して) 縮める。
     */
    fun place(
        surfaceWidthPx: Int,
        statusBarBottomPx: Float,
        density: Float,
        bitmapWidthPx: Int,
    ): OverlayPlacement {
        val ratio = if (pixelRatio > 0f) pixelRatio else density
        val padPx = paddingDp * ratio
        val rightPx = rightDp * density
        var scale = density / ratio
        val contentWidthPx = (bitmapWidthPx - 2 * padPx).coerceAtLeast(1f)
        val available = surfaceWidthPx - 2 * rightPx
        if (available > 0f && contentWidthPx * scale > available) {
            scale = available / contentWidthPx
        }
        val anchorX = surfaceWidthPx - rightPx
        val anchorY = statusBarBottomPx + topGapDp * density
        return OverlayPlacement(
            left = anchorX - (bitmapWidthPx - padPx) * scale,
            top = anchorY - padPx * scale,
            scale = scale,
        )
    }

    companion object {
        const val DEFAULT_PADDING_DP = 8f
        const val DEFAULT_RIGHT_DP = 24f
        const val DEFAULT_TOP_GAP_DP = 16f
        const val DEFAULT_STALE_AFTER_MILLIS = 3 * 60 * 60 * 1000L
        const val DEFAULT_FUTURE_TOLERANCE_MILLIS = 15 * 60 * 1000L

        /** ステータスバーの高さが insets からもリソースからも取れないときの値 (dp)。 */
        const val FALLBACK_STATUS_BAR_DP = 24f

        /**
         * setWallpaperOverlay の引数 (Dart の WallpaperOverlayPayload.toChannelArguments) から
         * 作る。データの時刻・2 枚の PNG・解像度が無い (または壊れている) ときは null。
         * 配置の数値が無いときは既定値。知らないキーは無視する。
         */
        fun fromChannelArguments(arguments: Any?): WallpaperOverlayUpdate? {
            val map = arguments as? Map<*, *> ?: return null
            val asOf = (map["asOf"] as? Number)?.toLong() ?: return null
            val fresh = (map["fresh"] as? ByteArray)?.takeIf { it.isNotEmpty() } ?: return null
            val stale = (map["stale"] as? ByteArray)?.takeIf { it.isNotEmpty() } ?: return null
            val ratio = (map["pixelRatio"] as? Number)?.toFloat()
                ?.takeIf { it.isFinite() && it > 0f } ?: return null

            fun dp(key: String, default: Float): Float =
                (map[key] as? Number)?.toFloat()?.takeIf { it.isFinite() && it >= 0f } ?: default

            fun minutes(key: String, default: Long): Long =
                (map[key] as? Number)?.toLong()?.takeIf { it > 0 }?.let { it * 60_000L } ?: default

            return WallpaperOverlayUpdate(
                spec = WallpaperOverlaySpec(
                    asOfMillis = asOf,
                    pixelRatio = ratio,
                    paddingDp = dp("paddingDp", DEFAULT_PADDING_DP),
                    rightDp = dp("rightDp", DEFAULT_RIGHT_DP),
                    topGapDp = dp("topGapDp", DEFAULT_TOP_GAP_DP),
                    staleAfterMillis = minutes("staleAfterMinutes", DEFAULT_STALE_AFTER_MILLIS),
                    futureToleranceMillis =
                    minutes("futureToleranceMinutes", DEFAULT_FUTURE_TOLERANCE_MILLIS),
                ),
                freshPng = fresh,
                stalePng = stale,
            )
        }
    }
}

/** ビットマップの左上の位置 (画素) と倍率。 */
data class OverlayPlacement(val left: Float, val top: Float, val scale: Float)

/** setWallpaperOverlay で届いた内容 (設定と 2 枚の PNG)。 */
class WallpaperOverlayUpdate(
    val spec: WallpaperOverlaySpec,
    val freshPng: ByteArray,
    val stalePng: ByteArray,
)
