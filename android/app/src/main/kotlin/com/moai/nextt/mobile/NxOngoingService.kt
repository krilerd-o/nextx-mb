package com.moai.nextt.mobile

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Rational
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A team call or a meeting room keeps going with the app in the background, shown in the notification
 * bar like a music player: title, status line, a running clock and buttons (ปิดไมค์ ⇄ เปิดไมค์ · วางสาย /
 * ออกจากห้อง · เปิด). One foreground service for both (type microphone, + camera while the camera is on);
 * each kind has its own notification. The media itself runs in Dart (WebRTC / LiveKit).
 *
 * Android 14+: a microphone / camera foreground service may only start while the app is visible — it
 * is started when the call connects or the room opens, which happens on screen.
 */
class NxOngoingService : Service() {
    data class Entry(
        val kind: String,
        val title: String,
        val subtitle: String,
        val micOn: Boolean,
        val video: Boolean,
        val startedAt: Long,
        val labels: Map<String, String>,
    )

    companion object {
        const val CHANNEL_ID = "nx_ongoing"
        const val ACTION_SYNC = "com.moai.nextt.mobile.ongoing.SYNC"
        const val ACTION_BUTTON = "com.moai.nextt.mobile.ongoing.BUTTON"
        const val EXTRA_KIND = "kind"
        const val EXTRA_ACTION = "action"
        const val EXTRA_OPEN_KIND = "nx_ongoing_open"

        /** Call first: it owns the foreground slot. */
        private val ORDER = listOf("call", "room")

        val entries = linkedMapOf<String, Entry>()
        @Volatile var running = false

        /** Button taps → Dart (set by [NxOngoingChannel]). */
        @Volatile var onAction: ((String, String) -> Unit)? = null

        fun notificationId(kind: String) = if (kind == "call") 7351 else 7352

        fun ensureChannel(ctx: Context) {
            val manager = ctx.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(CHANNEL_ID, "สายและห้องประชุม", NotificationManager.IMPORTANCE_LOW)
            channel.setSound(null, null)
            channel.enableVibration(false)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        private fun button(ctx: Context, kind: String, action: String, code: Int): PendingIntent {
            val i = Intent(ctx, NxOngoingService::class.java)
                .setAction(ACTION_BUTTON)
                .putExtra(EXTRA_KIND, kind)
                .putExtra(EXTRA_ACTION, action)
            return PendingIntent.getService(ctx, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun build(ctx: Context, e: Entry): Notification {
            val base = if (e.kind == "call") 100 else 200
            val open = Intent(ctx, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_OPEN_KIND, e.kind)
            val content = PendingIntent.getActivity(ctx, base, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            fun l(k: String, f: String) = e.labels[k] ?: f
            val b = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_mic)
                .setContentTitle(e.title)
                .setContentText(e.subtitle)
                .setSubText(if (e.micOn) null else l("muted", "Muted"))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setContentIntent(content)
                .setUsesChronometer(true)
                .setShowWhen(true)
                .setWhen(e.startedAt)
                .setColor(if (e.kind == "call") 0xFF16A34A.toInt() else 0xFF4F46E5.toInt())
                .addAction(0, if (e.micOn) l("mute", "Mute") else l("unmute", "Unmute"), button(ctx, e.kind, if (e.micOn) "mute" else "unmute", base + 1))
                .addAction(0, l("hangup", "Hang up"), button(ctx, e.kind, "hangup", base + 2))
                .addAction(0, l("open", "Open"), button(ctx, e.kind, "open", base + 3))
            return b.build()
        }

        fun foregroundType(ctx: Context): Int {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return 0
            var t = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            val camGranted = ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            if (camGranted && entries.values.any { it.video }) t = t or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            return t
        }

        fun lead(): Entry? = ORDER.firstNotNullOfOrNull { entries[it] } ?: entries.values.firstOrNull()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_BUTTON) {
            val kind = intent.getStringExtra(EXTRA_KIND) ?: return START_NOT_STICKY
            val action = intent.getStringExtra(EXTRA_ACTION) ?: return START_NOT_STICKY
            onAction?.invoke(kind, action)
            return START_NOT_STICKY
        }
        sync()
        return START_NOT_STICKY
    }

    /** Foreground notification = the lead entry; the others are plain ongoing notifications. */
    private fun sync() {
        ensureChannel(this)
        val manager = getSystemService(NotificationManager::class.java)
        val lead = lead()
        if (lead == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            for (k in ORDER) manager?.cancel(notificationId(k))
            running = false
            stopSelf()
            return
        }
        val n = build(this, lead)
        val type = foregroundType(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && type != 0) {
            startForeground(notificationId(lead.kind), n, type)
        } else {
            startForeground(notificationId(lead.kind), n)
        }
        running = true
        for (k in ORDER) {
            val e = entries[k]
            if (e == null) manager?.cancel(notificationId(k)) else if (e.kind != lead.kind) manager?.notify(notificationId(k), build(this, e))
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The app was swiped away: the call / room (in Dart) is gone with it.
        entries.clear()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}

/**
 * `nextx/ongoing`: show / hide a call or room in the notification bar, Picture-in-Picture on leaving the
 * app. Back to Dart: `action` {kind, action} (mute | unmute | hangup | open) and `pip` (bool).
 */
class NxOngoingChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "nextx/ongoing")
    private val main = Handler(Looper.getMainLooper())
    var activity: Activity? = null

    /** A video call / room is on: leaving the app goes to Picture-in-Picture. */
    @Volatile var pipEnabled = false
    @Volatile var pipAspect = Rational(9, 16)

    init {
        channel.setMethodCallHandler(this)
        NxOngoingService.onAction = { kind, action -> main.post { channel.invokeMethod("action", mapOf("kind" to kind, "action" to action)) } }
    }

    fun openFromNotification(kind: String) {
        main.post { channel.invokeMethod("action", mapOf("kind" to kind, "action" to "open")) }
    }

    fun pipChanged(inPip: Boolean) {
        main.post { channel.invokeMethod("pip", inPip) }
    }

    /** MainActivity.onUserLeaveHint: Home / recents during a video call → a small floating window. */
    fun enterPipIfWanted(): Boolean {
        val a = activity ?: return false
        if (!pipEnabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!a.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return try {
            a.enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(pipAspect).build())
        } catch (_: Exception) {
            false
        }
    }

    private fun startService(): Boolean {
        val i = Intent(context, NxOngoingService::class.java).setAction(NxOngoingService.ACTION_SYNC)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i) else context.startService(i)
            true
        } catch (_: Exception) {
            // Android 12+: not allowed from the background (ForegroundServiceStartNotAllowedException).
            false
        }
    }

    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                val kind = call.argument<String>("kind") ?: return result.error("args", "kind", null)
                NxOngoingService.entries[kind] = NxOngoingService.Entry(
                    kind = kind,
                    title = call.argument<String>("title") ?: "",
                    subtitle = call.argument<String>("subtitle") ?: "",
                    micOn = call.argument<Boolean>("micOn") ?: true,
                    video = call.argument<Boolean>("video") ?: false,
                    startedAt = (call.argument<Number>("startedAt") ?: System.currentTimeMillis()).toLong(),
                    labels = (call.argument<Map<String, String>>("labels") ?: emptyMap()),
                )
                if (startService()) result.success(null) else result.error("fg_service", "not allowed now", null)
            }
            "hide" -> {
                val kind = call.argument<String>("kind") ?: ""
                NxOngoingService.entries.remove(kind)
                if (NxOngoingService.running || NxOngoingService.entries.isNotEmpty()) startService()
                else context.getSystemService(NotificationManager::class.java)?.cancel(NxOngoingService.notificationId(kind))
                result.success(null)
            }
            "pip" -> {
                pipEnabled = call.argument<Boolean>("enabled") ?: false
                val aspect = (call.argument<Number>("aspect") ?: 0.5625).toDouble()
                pipAspect = Rational((aspect * 1000).toInt().coerceIn(420, 2390), 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Android 12+: swipe home goes straight to PiP (smoother than onUserLeaveHint).
                    try {
                        activity?.setPictureInPictureParams(PictureInPictureParams.Builder().setAspectRatio(pipAspect).setAutoEnterEnabled(pipEnabled).build())
                    } catch (_: Exception) {}
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
