package com.moai.nextt.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FragmentActivity: required by local_auth (fingerprint / face unlock).
class MainActivity: FlutterFragmentActivity() {
    private var micTap: CallMicTap? = null
    private var notebookRecorder: NotebookRecorderChannel? = null
    private var ongoing: NxOngoingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        micTap = CallMicTap(flutterEngine.dartExecutor.binaryMessenger)
        notebookRecorder = NotebookRecorderChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also { it.activity = this }
        ongoing = NxOngoingChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also { it.activity = this }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        notebookRecorder?.activity = null
        ongoing?.activity = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // The recording notification was tapped: show the recorder.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(NotebookRecordingService.EXTRA_OPEN, false)) notebookRecorder?.openFromNotification()
        intent.getStringExtra(NxOngoingService.EXTRA_OPEN_KIND)?.let { ongoing?.openFromNotification(it) }
    }

    // Home / recents during a video call or room: keep it in a small floating window.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) ongoing?.enterPipIfWanted()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        ongoing?.pipChanged(isInPictureInPictureMode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "high_importance_channel",
                "MOAI NEXT",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "แจ้งเตือนงานและแชท"
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
