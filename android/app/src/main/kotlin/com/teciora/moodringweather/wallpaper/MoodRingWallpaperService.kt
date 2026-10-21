package com.teciora.moodringweather.wallpaper

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import android.view.WindowInsets
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * MRI の区分に合わせて配色が変わるライブ壁紙 (5 区分、1 区分 1 配色) と、右上の
 * 天気・気温の重ね描き。
 *
 * 描くもの: 縦のグラデーション (地の 3 色) と、中心やや上の放射状の光。その上の右上に、
 * アプリが描いて渡したビットマップ (1 行目「グリフ + 気温」、2 行目「区分名 · 時刻」、
 * 古いデータなら「9/30 10:30 更新」「アプリを開くと更新」) を置く。時計・MRI の数値・
 * リング・ロゴは描かない。ホームのページ送りでは動かさない。
 *
 * 配色 (WallpaperPalette.forBand。docs/design-wallpaper-palette.md §0、2026-09-30 決裁):
 *   涼しい 80–100 (青) / 快適 60–79 (緑。OPTIMAL も同じ) / やや暑い 40–59 (琥珀) /
 *   暑い 20–39 (テラコッタ) / とても暑い 0–19 (赤。地の彩度と光を強める)。
 *   区分はアプリのリングと同じ (Dart の MriBand)。端末のライト / ダーク設定では変えない。
 *
 * 重ね描き (docs/design-wallpaper-weather-overlay.md、2026-09-30 決裁): 新しい表示と
 * 古い表示の 2 枚を、表示のたびにデータの時刻からの経過で選ぶ (3 時間超・時計が 15 分
 * 以上戻ったら古い表示)。表示中に 3 時間を超えたらその時刻に描き直す。設定でオフ・
 * 既定地点のときはアプリが消す (clearOverlay)。
 *
 * アプリ (MainActivity) が setMriState / setWallpaperOverlay / clearWallpaperOverlay を
 * 受けると内容を保存し、表示中なら即時に描き直す。アプリを開いていない間は更新しない。
 * 「データを削除」では clearMriState と clearWallpaperOverlay で保存を消し、既定 (快適の
 * 配色・重ね描きなし) に戻す。アプリが現在地の MRI を計算し直すと、通常どおり描き直す。
 */
class MoodRingWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = MoodRingEngine()

    companion object {
        private val updateHandler = Handler(Looper.getMainLooper())
        private val listeners = mutableSetOf<() -> Unit>()

        /** 重ね描きの PNG の書き込み・削除 (順番を保つため 1 本のスレッド)。 */
        private val overlayExecutor: ExecutorService by lazy {
            Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "mrw-wallpaper-overlay").apply { isDaemon = true }
            }
        }

        /** 壁紙が描く内容 (MRI・区分) を保存し、表示中のエンジンに描き直させる。 */
        fun update(context: Context, state: WallpaperState) {
            WallpaperStateStore.write(prefs(context), state)
            notifyChanged()
        }

        /**
         * 壁紙の色の状態 (MRI・区分) を消し、表示中のエンジンに描き直させる
         * (設定 › プライバシーの「データを削除」)。壁紙は既定 (MRI 64 = 快適の配色) に戻る。
         * 色の保存 ([update]) と同じ main スレッドで行い、届いた順に処理する。成否を返す。
         */
        fun clearState(context: Context): Boolean {
            val ok = runCatching { WallpaperStateStore.clear(prefs(context)) }.getOrDefault(false)
            notifyChanged()
            return ok
        }

        /**
         * 重ね描きを保存し (別スレッド)、表示中のエンジンに描き直させる。
         * [onDone] は保存の成否を main スレッドで受け取る。
         */
        fun updateOverlay(context: Context, update: WallpaperOverlayUpdate, onDone: (Boolean) -> Unit) {
            val app = context.applicationContext
            runOverlayTask(onDone) {
                WallpaperOverlayStore.write(prefs(app), overlayDir(app), update)
            }
        }

        /** 重ね描きを消し (別スレッド)、表示中のエンジンに描き直させる。 */
        fun clearOverlay(context: Context, onDone: (Boolean) -> Unit) {
            val app = context.applicationContext
            runOverlayTask(onDone) {
                WallpaperOverlayStore.clear(prefs(app), overlayDir(app))
            }
        }

        private fun runOverlayTask(onDone: (Boolean) -> Unit, task: () -> Unit) {
            overlayExecutor.execute {
                val ok = runCatching(task).isSuccess
                updateHandler.post {
                    if (ok) notifyListeners()
                    onDone(ok)
                }
            }
        }

        private fun notifyChanged() {
            updateHandler.post { notifyListeners() }
        }

        private fun notifyListeners() {
            listeners.toList().forEach { it.invoke() }
        }

        internal fun register(listener: () -> Unit) {
            listeners.add(listener)
        }

        internal fun unregister(listener: () -> Unit) {
            listeners.remove(listener)
        }

        internal fun readState(context: Context): WallpaperState =
            WallpaperStateStore.read(prefs(context))

        internal fun readOverlay(context: Context): WallpaperOverlayStore.Stored? =
            runCatching { WallpaperOverlayStore.read(prefs(context), overlayDir(context)) }
                .getOrNull()

        private fun prefs(context: Context) =
            context.getSharedPreferences(WallpaperStateStore.PREFS_NAME, Context.MODE_PRIVATE)

        private fun overlayDir(context: Context) =
            File(context.filesDir, WallpaperOverlayStore.DIRECTORY)
    }

    private inner class MoodRingEngine : Engine() {
        private val redrawListener = { redraw() }

        // 暗いグラデーションは 8 bit の段差が縞に見えやすいので、ディザをかける。
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG)
        private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

        private val handler = Handler(Looper.getMainLooper())
        private val staleSwitch = Runnable { redraw() }
        private var visible = false

        /** ステータスバーの下端 (onApplyWindowInsets。届かなければ 0)。 */
        private var statusBarInsetPx = 0

        /** 読み込んだ重ね描きの版と、表示ごとのビットマップ。 */
        private var overlayVersion: Long? = null
        private val overlayBitmaps = mutableMapOf<OverlayVariant, Bitmap>()

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            register(redrawListener)
        }

        override fun onDestroy() {
            handler.removeCallbacks(staleSwitch)
            unregister(redrawListener)
            releaseOverlay()
            super.onDestroy()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            if (visible) redraw() else handler.removeCallbacks(staleSwitch)
        }

        override fun onSurfaceChanged(
            holder: SurfaceHolder?,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            redraw()
        }

        override fun onApplyWindowInsets(insets: WindowInsets?) {
            super.onApplyWindowInsets(insets)
            val top = insets?.let { statusBarTop(it) } ?: 0
            if (top != statusBarInsetPx) {
                statusBarInsetPx = top
                redraw()
            }
        }

        private fun redraw() {
            val holder = surfaceHolder ?: return
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas()
                if (canvas != null) {
                    drawWallpaper(canvas, readState(this@MoodRingWallpaperService))
                    drawOverlay(canvas, System.currentTimeMillis())
                }
            } finally {
                if (canvas != null) holder.unlockCanvasAndPost(canvas)
            }
        }

        private fun drawWallpaper(canvas: Canvas, state: WallpaperState) {
            val w = canvas.width.toFloat()
            val h = canvas.height.toFloat()
            val palette = WallpaperPalette.forBand(state.band)

            // 地: 縦のグラデーション (上 → 中 → 下を均等に置く)
            paint.shader = LinearGradient(
                0f, 0f, 0f, h,
                palette.gradient,
                null,
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, w, h, paint)

            // 光: 中心 (0.5w, 0.35h) から外周へ不透明度が 0 になる放射状
            paint.shader = RadialGradient(
                w * 0.5f,
                h * 0.35f,
                max(w, h) * 0.5f,
                palette.glowCenter,
                palette.glowEdge,
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, w, h, paint)
            paint.shader = null
        }

        /** 右上の重ね描き。無ければ何もしない (壁紙は色だけ)。 */
        private fun drawOverlay(canvas: Canvas, nowMillis: Long) {
            handler.removeCallbacks(staleSwitch)
            val stored = readOverlay(this@MoodRingWallpaperService)
            if (stored == null) {
                releaseOverlay()
                return
            }
            if (stored.version != overlayVersion) {
                releaseOverlay()
                overlayVersion = stored.version
            }
            val variant = stored.spec.variantAt(nowMillis)
            val bitmap = overlayBitmap(stored, variant) ?: return
            val density = resources.displayMetrics.density
            val placement = stored.spec.place(
                surfaceWidthPx = canvas.width,
                statusBarBottomPx = statusBarBottomPx(density),
                density = density,
                bitmapWidthPx = bitmap.width,
            )
            canvas.save()
            canvas.translate(placement.left, placement.top)
            canvas.scale(placement.scale, placement.scale)
            canvas.drawBitmap(bitmap, 0f, 0f, bitmapPaint)
            canvas.restore()
            // 表示中に 3 時間を超えたら、その時刻に古い表示へ描き直す。
            if (visible) {
                stored.spec.millisUntilStale(nowMillis)?.let { handler.postDelayed(staleSwitch, it) }
            }
        }

        private fun overlayBitmap(stored: WallpaperOverlayStore.Stored, variant: OverlayVariant): Bitmap? =
            overlayBitmaps[variant]
                ?: BitmapFactory.decodeFile(stored.file(variant).path)
                    ?.also { overlayBitmaps[variant] = it }

        private fun releaseOverlay() {
            overlayBitmaps.values.forEach { it.recycle() }
            overlayBitmaps.clear()
            overlayVersion = null
        }

        /**
         * ステータスバーの下端 (画素)。WindowInsets の statusBars → ステータスバーの高さの
         * リソース → 24dp の順 (設計書 §3.1)。
         */
        private fun statusBarBottomPx(density: Float): Float {
            if (statusBarInsetPx > 0) return statusBarInsetPx.toFloat()
            val resource = statusBarHeightResourcePx()
            if (resource > 0) return resource.toFloat()
            return WallpaperOverlaySpec.FALLBACK_STATUS_BAR_DP * density
        }

        @SuppressLint("DiscouragedApi", "InternalInsetResource")
        private fun statusBarHeightResourcePx(): Int {
            val res = this@MoodRingWallpaperService.resources
            val id = res.getIdentifier("status_bar_height", "dimen", "android")
            return if (id > 0) res.getDimensionPixelSize(id) else 0
        }

        private fun statusBarTop(insets: WindowInsets): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                insets.getInsets(WindowInsets.Type.statusBars()).top
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop
            }
    }
}
