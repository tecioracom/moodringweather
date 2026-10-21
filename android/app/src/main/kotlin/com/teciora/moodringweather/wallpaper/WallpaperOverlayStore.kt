package com.teciora.moodringweather.wallpaper

import android.content.SharedPreferences
import java.io.File
import java.io.IOException

/**
 * 重ね描きの保存と読み出し。PNG 2 枚は filesDir/wallpaper_overlay/ に、設定は
 * SharedPreferences "mrw_wallpaper" (壁紙の色と同じファイル) に置く。
 *
 * ファイル名に版 (書くたびに 1 つ増える番号) を入れ、PNG を書き終えてから版を
 * SharedPreferences に書く。読む側は版で 2 枚を選ぶので、書いている途中でも古い組か
 * 新しい組のどちらかを読む (混ざらない)。版の番号は消しても戻さない (壁紙のエンジンが
 * 持っている古いビットマップを、同じ番号の新しい組と取り違えないため)。
 * PNG は一時ファイルに書いてから名前を変える。
 *
 * 書く・消すは別スレッドで呼ぶ (MoodRingWallpaperService.updateOverlay)。
 */
internal object WallpaperOverlayStore {
    const val DIRECTORY = "wallpaper_overlay"

    private const val KEY_SERIAL = "overlay_serial"
    private const val KEY_VERSION = "overlay_version"
    private const val KEY_AS_OF = "overlay_as_of"
    private const val KEY_PIXEL_RATIO = "overlay_pixel_ratio"
    private const val KEY_PADDING_DP = "overlay_padding_dp"
    private const val KEY_RIGHT_DP = "overlay_right_dp"
    private const val KEY_TOP_GAP_DP = "overlay_top_gap_dp"
    private const val KEY_STALE_AFTER_MS = "overlay_stale_after_ms"
    private const val KEY_FUTURE_TOLERANCE_MS = "overlay_future_tolerance_ms"

    /** 保存されている重ね描き。 */
    data class Stored(
        val version: Long,
        val spec: WallpaperOverlaySpec,
        val fresh: File,
        val stale: File,
    ) {
        fun file(variant: OverlayVariant): File =
            if (variant == OverlayVariant.FRESH) fresh else stale
    }

    fun write(prefs: SharedPreferences, dir: File, update: WallpaperOverlayUpdate): Long {
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("mkdirs failed: $dir")
        val version = prefs.getLong(KEY_SERIAL, 0L) + 1
        writeAtomically(fileFor(dir, version, OverlayVariant.FRESH), update.freshPng)
        writeAtomically(fileFor(dir, version, OverlayVariant.STALE), update.stalePng)
        val spec = update.spec
        val committed = prefs.edit()
            .putLong(KEY_SERIAL, version)
            .putLong(KEY_VERSION, version)
            .putLong(KEY_AS_OF, spec.asOfMillis)
            .putFloat(KEY_PIXEL_RATIO, spec.pixelRatio)
            .putFloat(KEY_PADDING_DP, spec.paddingDp)
            .putFloat(KEY_RIGHT_DP, spec.rightDp)
            .putFloat(KEY_TOP_GAP_DP, spec.topGapDp)
            .putLong(KEY_STALE_AFTER_MS, spec.staleAfterMillis)
            .putLong(KEY_FUTURE_TOLERANCE_MS, spec.futureToleranceMillis)
            .commit()
        if (!committed) throw IOException("SharedPreferences commit failed")
        deleteOtherVersions(dir, keep = version)
        return version
    }

    /** 重ね描きを消す (設定・PNG)。版の番号 (KEY_SERIAL) は残す。 */
    fun clear(prefs: SharedPreferences, dir: File) {
        val committed = prefs.edit()
            .remove(KEY_VERSION)
            .remove(KEY_AS_OF)
            .remove(KEY_PIXEL_RATIO)
            .remove(KEY_PADDING_DP)
            .remove(KEY_RIGHT_DP)
            .remove(KEY_TOP_GAP_DP)
            .remove(KEY_STALE_AFTER_MS)
            .remove(KEY_FUTURE_TOLERANCE_MS)
            .commit()
        if (!committed) throw IOException("SharedPreferences commit failed")
        deleteOtherVersions(dir, keep = null)
    }

    /** 保存されている重ね描き。無い・PNG が欠けている・設定が壊れているときは null。 */
    fun read(prefs: SharedPreferences, dir: File): Stored? {
        if (!prefs.contains(KEY_VERSION)) return null
        val version = prefs.getLong(KEY_VERSION, 0L)
        val fresh = fileFor(dir, version, OverlayVariant.FRESH)
        val stale = fileFor(dir, version, OverlayVariant.STALE)
        if (!fresh.isFile || !stale.isFile) return null
        val ratio = prefs.getFloat(KEY_PIXEL_RATIO, 0f)
        if (!ratio.isFinite() || ratio <= 0f) return null
        val spec = WallpaperOverlaySpec(
            asOfMillis = prefs.getLong(KEY_AS_OF, 0L),
            pixelRatio = ratio,
            paddingDp = prefs.getFloat(KEY_PADDING_DP, WallpaperOverlaySpec.DEFAULT_PADDING_DP),
            rightDp = prefs.getFloat(KEY_RIGHT_DP, WallpaperOverlaySpec.DEFAULT_RIGHT_DP),
            topGapDp = prefs.getFloat(KEY_TOP_GAP_DP, WallpaperOverlaySpec.DEFAULT_TOP_GAP_DP),
            staleAfterMillis = prefs.getLong(
                KEY_STALE_AFTER_MS,
                WallpaperOverlaySpec.DEFAULT_STALE_AFTER_MILLIS,
            ),
            futureToleranceMillis = prefs.getLong(
                KEY_FUTURE_TOLERANCE_MS,
                WallpaperOverlaySpec.DEFAULT_FUTURE_TOLERANCE_MILLIS,
            ),
        )
        return Stored(version, spec, fresh, stale)
    }

    fun fileFor(dir: File, version: Long, variant: OverlayVariant): File =
        File(dir, "overlay_${version}_${variant.name.lowercase()}.png")

    private fun writeAtomically(target: File, bytes: ByteArray) {
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeBytes(bytes)
        if (!temp.renameTo(target)) {
            target.delete()
            if (!temp.renameTo(target)) {
                temp.delete()
                throw IOException("rename failed: $target")
            }
        }
    }

    /** [keep] の版の PNG 以外を消す (null ならすべて)。 */
    private fun deleteOtherVersions(dir: File, keep: Long?) {
        val kept = keep?.let {
            setOf(
                fileFor(dir, it, OverlayVariant.FRESH).name,
                fileFor(dir, it, OverlayVariant.STALE).name,
            )
        } ?: emptySet()
        dir.listFiles()?.forEach { file ->
            if (file.name !in kept) file.delete()
        }
    }
}
