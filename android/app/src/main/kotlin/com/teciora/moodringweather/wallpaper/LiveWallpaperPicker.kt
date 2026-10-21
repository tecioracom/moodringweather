package com.teciora.moodringweather.wallpaper

import android.app.WallpaperManager

/**
 * アプリからライブ壁紙を設定する手順 (設定 › 一般 › ライブ壁紙「ライブ壁紙を設定」。
 * 1.3.0 (14))。
 *
 * 背景 (2026-10-01 実機で発見): Galaxy (One UI) の「壁紙とスタイル」は他社アプリの
 * ライブ壁紙を一覧に出さないため、端末の壁紙設定からはこの壁紙を選べない。アプリから
 * 壁紙のプレビュー画面を開く。
 *
 * 試す順:
 *   ① ACTION_CHANGE_LIVE_WALLPAPER + EXTRA_LIVE_WALLPAPER_COMPONENT (この壁紙のプレビュー)
 *   ② ACTION_LIVE_WALLPAPER_CHOOSER (ライブ壁紙の一覧。① が無い端末)
 *   ③ どちらも開けなければ false (Dart が「端末の壁紙設定から選んでください」と案内する)
 *
 * android.content.Intent は JVM のユニットテストで動かないので、ここでは「何を試すか」と
 * 「順に試す」だけを持ち、Intent の組み立てと起動は MainActivity が行う。
 * Java の static final の文字列定数 (WallpaperManager.ACTION_*) はコンパイル時に
 * 埋め込まれるので、JVM テストでも値を読める。
 */
object LiveWallpaperPicker {
    /**
     * 試す画面の 1 つ。
     *
     * @property action Intent の action。
     * @property withComponent true なら EXTRA_LIVE_WALLPAPER_COMPONENT にこの壁紙
     *   (MoodRingWallpaperService) を付ける (プレビューを直接開く)。
     */
    data class Attempt(val action: String, val withComponent: Boolean)

    /** 試す順 (① プレビュー → ② 一覧)。 */
    val ATTEMPTS: List<Attempt> = listOf(
        Attempt(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER, withComponent = true),
        Attempt(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER, withComponent = false),
    )

    /**
     * [attempts] を順に [launch] し、最初に開けた (例外が出なかった) ところで true。
     * すべて例外 (ActivityNotFoundException・SecurityException など) なら false。
     * 例外は外へ出さない。
     */
    fun open(attempts: List<Attempt> = ATTEMPTS, launch: (Attempt) -> Unit): Boolean {
        for (attempt in attempts) {
            try {
                launch(attempt)
                return true
            } catch (e: Exception) {
                // 次の手段へ。
            }
        }
        return false
    }

    /**
     * 今の壁紙 (WallpaperManager.getWallpaperInfo().component) がこのアプリの
     * ライブ壁紙か。ライブ壁紙でない (静止画) ときは [activePackage] / [activeClass] が null。
     */
    fun isOwnWallpaper(
        activePackage: String?,
        activeClass: String?,
        ownPackage: String,
        ownClass: String,
    ): Boolean = activePackage == ownPackage && activeClass == ownClass
}
