package com.moai.nextt.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FragmentActivity: required by local_auth (fingerprint / face unlock).
class MainActivity: FlutterFragmentActivity() {
    private var micTap: CallMicTap? = null
    private var notebookRecorder: NotebookRecorderChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        micTap = CallMicTap(flutterEngine.dartExecutor.binaryMessenger)
        notebookRecorder = NotebookRecorderChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also { it.activity = this }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        notebookRecorder?.activity = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // The recording notification was tapped: show the recorder.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(NotebookRecordingService.EXTRA_OPEN, false)) notebookRecorder?.openFromNotification()
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
