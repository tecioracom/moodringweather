package com.teciora.moodringweather

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import com.teciora.moodringweather.wallpaper.LiveWallpaperPicker
import com.teciora.moodringweather.wallpaper.MoodRingWallpaperService
import com.teciora.moodringweather.wallpaper.WallpaperOverlaySpec
import com.teciora.moodringweather.wallpaper.WallpaperState
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 側からライブ壁紙を起動・更新するための MethodChannel ホスト。
 *
 * 仕様: spec.md §8 / §15.2 v1.1 — Android ライブ壁紙 (MRI の 5 区分)。
 *
 * メソッド:
 *   isLiveWallpaperSupported()         -> Boolean
 *   openLiveWallpaperPicker()          -> Boolean  (壁紙のプレビュー → 無ければ一覧を開く。
 *                                                   どちらも開けなければ false。1.3.0 (14))
 *   isLiveWallpaperActive()            -> Boolean  (今のホーム画面の壁紙がこのライブ壁紙か。
 *                                                   失敗は false。1.3.0 (14))
 *   setMriState({mri: Int, band: String}) -> Boolean  (壁紙の色: MRI と区分名)
 *   setWallpaperOverlay({asOf, fresh, stale, pixelRatio, ...}) -> Boolean
 *                                      (右上の重ね描き: 新しい / 古い表示の PNG 2 枚)
 *   clearWallpaperOverlay()            -> Boolean  (重ね描きを消す: 設定でオフ・既定地点・データ削除)
 *   clearMriState()                    -> Boolean  (色の状態を消す: データ削除。既定の快適の配色へ)
 *
 * setMriState の引数は Dart の WallpaperState.toChannelArguments と 1:1
 * (Kotlin 側は wallpaper/WallpaperState.kt)。band (区分名) は 1.3.0 (13) から。
 * 重ね描き (1.3.0 (13) から) の引数は Dart の WallpaperOverlayPayload と 1:1
 * (Kotlin 側は wallpaper/WallpaperOverlay.kt)。色とは別のメソッドで、重ね描きが
 * 失敗しても色の更新は止めない。PNG の保存は別スレッドで行い、終わってから返事をする。
 *
 * 壁紙の設定 (openLiveWallpaperPicker / isLiveWallpaperActive) は設定 › 一般 › ライブ壁紙の
 * 「ライブ壁紙を設定」から呼ばれる (Dart の LiveWallpaperSetupBridge)。Galaxy (One UI) の
 * 「壁紙とスタイル」は他社アプリのライブ壁紙を一覧に出さないため (2026-10-01 実機で発見)。
 * 試す順と判定は wallpaper/LiveWallpaperPicker.kt。
 */
class MainActivity : FlutterActivity() {
    // MethodChannel 名は applicationId と独立だが、ID 移行に合わせて統一。
    // Flutter 側 (今後の wallpaper 連携実装) は必ずこの文字列を使うこと。
    private val channelName = "com.teciora.moodringweather/wallpaper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLiveWallpaperSupported" -> result.success(true)
                    "openLiveWallpaperPicker" -> result.success(openPicker())
                    "isLiveWallpaperActive" -> result.success(isLiveWallpaperActive())
                    "setMriState" -> {
                        // mri と band (区分名)。区分名が無ければ従来どおり MRI の値だけで描く。
                        // 知らないキーは無視する。
                        MoodRingWallpaperService.update(
                            applicationContext,
                            WallpaperState.fromChannelArguments(call.arguments),
                        )
                        result.success(true)
                    }
                    "clearMriState" -> {
                        // 設定 › プライバシーの「データを削除」。色の保存と同じ main スレッドで消す。
                        result.success(MoodRingWallpaperService.clearState(applicationContext))
                    }
                    "setWallpaperOverlay" -> {
                        val update = WallpaperOverlaySpec.fromChannelArguments(call.arguments)
                        if (update == null) {
                            result.success(false)
                        } else {
                            MoodRingWallpaperService.updateOverlay(applicationContext, update) {
                                result.success(it)
                            }
                        }
                    }
                    "clearWallpaperOverlay" -> {
                        MoodRingWallpaperService.clearOverlay(applicationContext) {
                            result.success(it)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 壁紙のプレビュー画面を開く。① この壁紙のプレビュー → ② ライブ壁紙の一覧 の順に試し、
     * どちらも開けなければ false (LiveWallpaperPicker.ATTEMPTS)。
     */
    private fun openPicker(): Boolean {
        val component = ComponentName(applicationContext, MoodRingWallpaperService::class.java)
        return LiveWallpaperPicker.open { attempt ->
            val intent = Intent(attempt.action)
            if (attempt.withComponent) {
                intent.putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
            }
            startActivity(intent)
        }
    }

    /** 今のホーム画面の壁紙がこのアプリのライブ壁紙か。取れなければ false。 */
    private fun isLiveWallpaperActive(): Boolean {
        return try {
            val active = WallpaperManager.getInstance(applicationContext).wallpaperInfo?.component
            LiveWallpaperPicker.isOwnWallpaper(
                activePackage = active?.packageName,
                activeClass = active?.className,
                ownPackage = applicationContext.packageName,
                ownClass = MoodRingWallpaperService::class.java.name,
            )
        } catch (e: Exception) {
            false
        }
    }
}
