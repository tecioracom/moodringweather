package com.teciora.moodringweather.wallpaper

/**
 * 壁紙が描く内容。Dart の WallpaperState (lib/data/wallpaper/wallpaper_bridge.dart) が
 * MethodChannel の setMriState で送る引数 (Map) と 1:1 で、同じ項目で保存する
 * (WallpaperStateStore)。
 *
 * 引数 (1.3.0 (13) から):
 *   "mri"  : Int    MRI 0–100
 *   "band" : String 区分名 (MriBand.name)。配色はこれで決まる
 *
 * 項目を足すとき (気温の表示文字列・天気の種類・更新時刻など) は、null 可のプロパティとして
 * 足し (古い保存データ・古い引数には無い)、[fromChannelArguments] と WallpaperStateStore の
 * 保存・読み出しに 1 行ずつ足す。知らないキーは無視するので、Dart が先にキーを足しても壊れない。
 */
data class WallpaperState(
    /** MRI 0–100。区分名が無いときの区分の決定と、古いデータとの互換のために持つ。 */
    val mri: Int = DEFAULT_MRI,
    /** 区分名 (MriBand.name)。1.3.0 (12) までの保存データには無い (null)。 */
    val bandKey: String? = null,
) {
    /** 描く区分。区分名を優先し、無い・知らない名前のときだけ MRI の値で決める。 */
    val band: WallpaperBand
        get() = WallpaperBand.fromKey(bandKey) ?: WallpaperBand.fromMri(mri)

    companion object {
        /** MRI が無いときの値。64 = 快適 (MRI のアンカー。docs/mri-spec.md §3.2)。 */
        const val DEFAULT_MRI = 64

        /**
         * setMriState の引数 (MethodCall.arguments) から作る。Map でない・MRI が無い・型が違う
         * ときは MRI 64。区分名が文字列でなければ区分名なし。MRI は 0–100 に丸める。
         */
        fun fromChannelArguments(arguments: Any?): WallpaperState {
            val map = arguments as? Map<*, *> ?: return WallpaperState()
            val mri = (map["mri"] as? Number)?.toInt() ?: DEFAULT_MRI
            return WallpaperState(
                mri = mri.coerceIn(0, 100),
                bandKey = map["band"] as? String,
            )
        }
    }
}
