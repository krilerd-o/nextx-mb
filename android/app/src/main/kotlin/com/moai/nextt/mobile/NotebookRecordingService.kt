package com.moai.nextt.mobile

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Keeps an ISAAC Notebook recording running with the screen off or the app in the background:
 * a foreground service of type `microphone` with an ongoing notification (elapsed time as a
 * chronometer, actions หยุดชั่วคราว / อัดต่อ / จบ). The audio itself is recorded in Dart (`record`
 * plugin); this service only keeps the process in the foreground so Android does not cut the mic.
 *
 * Android 14+: a microphone foreground service may only start while the app is visible — it is
 * started when the user taps "เริ่มบันทึก", which is always in the foreground.
 */
class NotebookRecordingService : Service() {
    companion object {
        const val CHANNEL_ID = "notebook_recording"
        const val NOTIFICATION_ID = 7341
        const val ACTION_START = "com.moai.nextt.mobile.notebook.START"
        const val ACTION_PAUSE = "com.moai.nextt.mobile.notebook.PAUSE"
        const val ACTION_RESUME = "com.moai.nextt.mobile.notebook.RESUME"
        const val ACTION_STOP = "com.moai.nextt.mobile.notebook.STOP"
        const val EXTRA_OPEN = "notebook_recorder_open"

        /** Taps on the notification actions → Dart (set by [NotebookRecorderChannel]). */
        @Volatile var onAction: ((String) -> Unit)? = null

        // Last state (the service can be re-created by the system).
        @Volatile var title: String = ""
        @Volatile var paused: Boolean = false
        @Volatile var elapsedMs: Long = 0
        @Volatile var stampedAt: Long = 0
        @Volatile var labels: Map<String, String> = emptyMap()
        @Volatile var running: Boolean = false

        private fun label(key: String, fallback: String) = labels[key] ?: fallback

        fun ensureChannel(ctx: Context) {
            val manager = ctx.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(CHANNEL_ID, label("channel", "Notebook recording"), NotificationManager.IMPORTANCE_LOW)
            channel.setSound(null, null)
            channel.enableVibration(false)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        private fun servicePending(ctx: Context, action: String, code: Int): PendingIntent {
            val i = Intent(ctx, NotebookRecordingService::class.java).setAction(action)
            return PendingIntent.getService(ctx, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun build(ctx: Context): Notification {
            val open = Intent(ctx, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_OPEN, true)
            val content = PendingIntent.getActivity(ctx, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val elapsedNow = if (paused) elapsedMs else elapsedMs + (System.currentTimeMillis() - stampedAt)
            val b = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_mic)
                .setContentTitle(title.ifEmpty { label("recording", "Recording") })
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setContentIntent(content)
                .setColor(0xFFDB2777.toInt())
            if (paused) {
                b.setUsesChronometer(false)
                    .setShowWhen(false)
                    .setContentText("${label("paused", "Paused")} · ${clock(elapsedNow)}")
                    .addAction(0, label("resume", "Resume"), servicePending(ctx, ACTION_RESUME, 2))
            } else {
                b.setUsesChronometer(true)
                    .setShowWhen(true)
                    .setWhen(System.currentTimeMillis() - elapsedNow)
                    .setContentText(label("recording", "Recording"))
                    .addAction(0, label("pause", "Pause"), servicePending(ctx, ACTION_PAUSE, 1))
            }
            b.addAction(0, label("stop", "Stop"), servicePending(ctx, ACTION_STOP, 3))
            return b.build()
        }

        private fun clock(ms: Long): String {
            val s = ms / 1000
            val h = s / 3600
            val m = (s % 3600) / 60
            val r = s % 60
            return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, r) else String.format(Locale.ROOT, "%02d:%02d", m, r)
        }

        /** Re-posts the ongoing notification (updating a running foreground service needs no restart). */
        fun refresh(ctx: Context) {
            if (!running) return
            ensureChannel(ctx)
            ctx.getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, build(ctx))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> {
                onAction?.invoke("pause")
                return START_NOT_STICKY
            }
            ACTION_RESUME -> {
                onAction?.invoke("resume")
                return START_NOT_STICKY
            }
            ACTION_STOP -> {
                onAction?.invoke("stop")
                return START_NOT_STICKY
            }
        }
        ensureChannel(this)
        val notification = build(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The app was swiped away: the recorder (in Dart) is gone with it.
        stopForegroundCompat()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}

/** `nextx/notebook_recorder`: start / update / stop the service, `background`; actions back as `action`. */
class NotebookRecorderChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "nextx/notebook_recorder")
    private val main = Handler(Looper.getMainLooper())
    var activity: Activity? = null

    init {
        channel.setMethodCallHandler(this)
        NotebookRecordingService.onAction = { a -> main.post { channel.invokeMethod("action", a) } }
    }

    fun openFromNotification() {
        main.post { channel.invokeMethod("action", "open") }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start", "update" -> {
                call.argument<String>("title")?.let { NotebookRecordingService.title = it }
                call.argument<Map<String, String>>("labels")?.let { NotebookRecordingService.labels = it }
                NotebookRecordingService.paused = call.argument<Boolean>("paused") ?: false
                NotebookRecordingService.elapsedMs = (call.argument<Number>("elapsedMs") ?: 0).toLong()
                NotebookRecordingService.stampedAt = System.currentTimeMillis()
                if (call.method == "update") {
                    NotebookRecordingService.refresh(context)
                    result.success(null)
                    return
                }
                val i = Intent(context, NotebookRecordingService::class.java).setAction(NotebookRecordingService.ACTION_START)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i) else context.startService(i)
                    result.success(null)
                } catch (e: Exception) {
                    // Android 12+: not allowed from the background (ForegroundServiceStartNotAllowedException).
                    result.error("fg_service", e.message, null)
                }
            }
            "stop" -> {
                context.stopService(Intent(context, NotebookRecordingService::class.java))
                NotebookRecordingService.running = false
                result.success(null)
            }
            "background" -> {
                // Back on the first screen while recording: keep the app (and the recording) alive.
                result.success(activity?.moveTaskToBack(true) ?: false)
            }
            else -> result.notImplemented()
        }
    }
}
