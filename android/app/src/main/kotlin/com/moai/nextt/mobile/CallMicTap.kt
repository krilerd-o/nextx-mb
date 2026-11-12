package com.moai.nextt.mobile

import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.AudioTrackSink
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Live captions during a call: reads the microphone audio WebRTC already captures (after echo
 * cancellation) instead of opening a second recorder, so the call and the transcriber never fight
 * over the mic. Emits PCM16 mono 24 kHz in 100 ms packets (4800 bytes) on `nextx/call_mic_tap/pcm`.
 */
class CallMicTap(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, AudioTrackSink {
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var track: LocalAudioTrack? = null
    private val out = ByteArrayOutputStream()
    private var phase = 0.0

    init {
        MethodChannel(messenger, "nextx/call_mic_tap").setMethodCallHandler(this)
        EventChannel(messenger, "nextx/call_mic_tap/pcm").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val id = call.argument<String>("trackId")
                val t = id?.let { FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(it) } as? LocalAudioTrack
                if (t == null) {
                    result.error("no_track", "local audio track not found", null)
                    return
                }
                stop()
                synchronized(out) {
                    out.reset()
                    phase = 0.0
                }
                track = t
                t.addSink(this)
                result.success(true)
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun stop() {
        track?.removeSink(this)
        track = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
        stop()
    }

    /** 10 ms frames from WebRTC's audio thread → mono → 24 kHz (linear) → 100 ms packets. */
    override fun onData(audioData: ByteBuffer, bitsPerSample: Int, sampleRate: Int, numberOfChannels: Int, numberOfFrames: Int, absoluteCaptureTimestampMs: Long) {
        if (bitsPerSample != 16 || sampleRate <= 0 || numberOfChannels <= 0) return
        val buf = audioData.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        buf.rewind()
        val frames = minOf(numberOfFrames, buf.remaining() / (2 * numberOfChannels))
        if (frames <= 0) return
        val mono = ShortArray(frames)
        for (i in 0 until frames) {
            var sum = 0
            for (c in 0 until numberOfChannels) sum += buf.short.toInt()
            mono[i] = (sum / numberOfChannels).toShort()
        }
        val packets = ArrayList<ByteArray>(1)
        synchronized(out) {
            val step = sampleRate / 24000.0
            while (phase < frames - 1) {
                val i = phase.toInt()
                val f = phase - i
                val s = (mono[i] * (1 - f) + mono[i + 1] * f).toInt()
                out.write(s and 0xff)
                out.write((s shr 8) and 0xff)
                phase += step
            }
            phase -= frames
            if (phase < 0) phase = 0.0
            while (out.size() >= PACKET) {
                val all = out.toByteArray()
                packets.add(all.copyOfRange(0, PACKET))
                out.reset()
                out.write(all, PACKET, all.size - PACKET)
            }
        }
        for (p in packets) main.post { events?.success(p) }
    }

    companion object {
        private const val PACKET = 4800
    }
}
