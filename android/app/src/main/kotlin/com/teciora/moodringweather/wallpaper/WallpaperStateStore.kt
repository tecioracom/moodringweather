package com.teciora.moodringweather.wallpaper

import android.content.SharedPreferences

/**
 * WallpaperState の保存と読み出し (SharedPreferences "mrw_wallpaper")。
 *
 * キー:
 *   "mri"  : Int    1.1 から。無いときは 64 (快適)
 *   "band" : String 1.3.0 (13) から。無い (古い保存データ) ときは MRI の値で区分を決める
 *
 * 項目を足すときは、キーを足して [write] と [read] と [clear] に 1 行ずつ足す。
 */
internal object WallpaperStateStore {
    const val PREFS_NAME = "mrw_wallpaper"
    private const val KEY_MRI = "mri"
    private const val KEY_BAND = "band"

    fun write(prefs: SharedPreferences, state: WallpaperState) {
        val editor = prefs.edit().putInt(KEY_MRI, state.mri.coerceIn(0, 100))
        // 区分名が無いときは消す。前回の区分名が残ると、値と違う区分の色で描いてしまう。
        val band = state.bandKey
        if (band != null) editor.putString(KEY_BAND, band) else editor.remove(KEY_BAND)
        editor.apply()
    }

    /**
     * 保存を消す (設定 › プライバシーの「データを削除」)。消した後は [read] が既定
     * (MRI 64・区分名なし = 快適の配色) を返す。ディスクまで書いてから返す (成否を返す)。
     */
    fun clear(prefs: SharedPreferences): Boolean =
        prefs.edit().remove(KEY_MRI).remove(KEY_BAND).commit()

    fun read(prefs: SharedPreferences): WallpaperState = WallpaperState(
        mri = prefs.getInt(KEY_MRI, WallpaperState.DEFAULT_MRI),
        bandKey = prefs.getString(KEY_BAND, null),
    )
}
