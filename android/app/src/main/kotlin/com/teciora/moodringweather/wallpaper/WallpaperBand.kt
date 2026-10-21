package com.teciora.moodringweather.wallpaper

/**
 * ライブ壁紙の区分。Dart の MriBand (lib/domain/mri/mri_band.dart) と 1:1 で、
 * [key] は MriBand.name (setMriState の引数 "band" で届く値)。
 *
 * 区分を決める正本は Dart の MriBand.fromValue (アプリのリングと同じ関数)。Kotlin は
 * 区分 → 配色の表 (WallpaperPalette.forBand) だけを持ち、境界 ([fromMri]) を使うのは
 * 区分名の無い古い保存データ (1.3.0 (12) まで) と、知らない名前が届いたときだけ。
 */
enum class WallpaperBand(val key: String) {
    /** 80–100 涼しい。 */
    COOL("cool"),

    /** 60–79 快適 (OPTIMAL を含む。OPTIMAL は区分ではなくラベルだけの違い)。 */
    COMFORTABLE("comfortable"),

    /** 40–59 やや暑い。 */
    WARM("warm"),

    /** 20–39 暑い。 */
    HOT("hot"),

    /** 0–19 とても暑い。 */
    HOT_ALERT("hotAlert"),
    ;

    companion object {
        /** 区分名 (MriBand.name) → 区分。null・知らない名前は null (大文字と小文字は区別する)。 */
        fun fromKey(key: String?): WallpaperBand? =
            if (key == null) null else entries.firstOrNull { it.key == key }

        /**
         * MRI → 区分。区分名の無い古いデータ用の写しで、境界は
         * lib/domain/mri/mri_band.dart の MriBand.fromValue と同じ (下端を含む: 80 / 60 / 40 / 20)。
         * 境界を変えるときは Dart 側と、両方のテスト (test/unit/wallpaper_bridge_test.dart・
         * src/test の WallpaperBandTest) も直す。
         */
        fun fromMri(mri: Int): WallpaperBand = when {
            mri >= 80 -> COOL
            mri >= 60 -> COMFORTABLE
            mri >= 40 -> WARM
            mri >= 20 -> HOT
            else -> HOT_ALERT
        }
    }
}
