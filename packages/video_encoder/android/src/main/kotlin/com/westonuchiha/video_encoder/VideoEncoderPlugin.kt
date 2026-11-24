package com.westonuchiha.video_encoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Writes MP4 (H.264 + AAC) with the phone's own encoders.
 *
 * Method channel "video_encoder":
 *   start {path, width, height, fps, bitrate, sampleRate, channels, audio}
 *   frame {data: I420 bytes, index}
 *   audio {data: 16-bit interleaved PCM, offset: sample frames so far}
 *   finish / cancel
 * Work runs on one background thread, in call order.
 */
class VideoEncoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var session: Session? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "video_encoder")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.execute {
            session?.release()
            session = null
        }
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                handle(call)
                main.post { result.success(null) }
            } catch (e: Throwable) {
                main.post { result.error("encoder", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun handle(call: MethodCall) {
        when (call.method) {
            "start" -> {
                session?.release()
                session = null
                session = Session(
                    call.argument<String>("path")!!,
                    call.argument<Int>("width")!!,
                    call.argument<Int>("height")!!,
                    call.argument<Int>("fps")!!,
                    call.argument<Int>("bitrate")!!,
                    call.argument<Int>("sampleRate")!!,
                    call.argument<Int>("channels")!!,
                    call.argument<Boolean>("audio")!!,
                )
            }
            "frame" -> current().frame(
                call.argument<ByteArray>("data")!!,
                (call.argument<Number>("index")!!).toLong(),
            )
            "audio" -> current().audio(
                call.argument<ByteArray>("data")!!,
                (call.argument<Number>("offset")!!).toLong(),
            )
            "finish" -> {
                val s = current()
                session = null
                s.finish()
            }
            "cancel" -> {
                session?.release()
                session = null
            }
            else -> throw IllegalArgumentException("Unknown method ${call.method}")
        }
    }

    private fun current(): Session = session ?: throw IllegalStateException("No video is being written")
}

private class Pending(val track: Int, val data: ByteBuffer, val info: MediaCodec.BufferInfo)

private class Session(
    path: String,
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    bitrate: Int,
    private val sampleRate: Int,
    private val channels: Int,
    private val hasAudio: Boolean,
) {
    private val muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val video: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val audio: MediaCodec? = if (hasAudio) MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC) else null
    private var videoTrack = -1
    private var audioTrack = -1
    private var started = false
    private val pending = ArrayList<Pending>()
    private val info = MediaCodec.BufferInfo()
    private var lastVideoUs = 0L
    private var lastAudioUs = 0L

    init {
        try {
            val vf = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
            vf.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            vf.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            vf.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            vf.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            video.configure(vf, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            video.start()
            audio?.let {
                val af = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels)
                af.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                af.setInteger(MediaFormat.KEY_BIT_RATE, 128000 * channels / 2 + 64000)
                af.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384 * channels)
                it.configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                it.start()
            }
        } catch (e: Throwable) {
            release()
            throw e
        }
    }

    fun frame(i420: ByteArray, index: Long) {
        val pts = index * 1_000_000L / fps
        lastVideoUs = pts
        var idx: Int
        while (true) {
            idx = video.dequeueInputBuffer(10_000)
            if (idx >= 0) break
            drain(video, false)
        }
        val image = video.getInputImage(idx) ?: throw IllegalStateException("Encoder gave no input image")
        val cw = width / 2
        val ch = height / 2
        val planes = image.planes
        // Y
        copyPlane(i420, 0, width, height, planes[0])
        // U then V
        copyPlane(i420, width * height, cw, ch, planes[1])
        copyPlane(i420, width * height + cw * ch, cw, ch, planes[2])
        video.queueInputBuffer(idx, 0, width * height * 3 / 2, pts, 0)
        drain(video, false)
    }

    private fun copyPlane(src: ByteArray, offset: Int, w: Int, h: Int, plane: android.media.Image.Plane) {
        val buf = plane.buffer
        val row = plane.rowStride
        val px = plane.pixelStride
        if (px == 1) {
            for (y in 0 until h) {
                buf.position(y * row)
                buf.put(src, offset + y * w, w)
            }
        } else {
            for (y in 0 until h) {
                val base = y * row
                val s = offset + y * w
                for (x in 0 until w) {
                    buf.put(base + x * px, src[s + x])
                }
            }
        }
    }

    fun audio(pcm: ByteArray, offsetFrames: Long) {
        val codec = audio ?: return
        val frameBytes = 2 * channels
        var pos = 0
        while (pos < pcm.size) {
            val idx = codec.dequeueInputBuffer(10_000)
            if (idx < 0) {
                drain(codec, false)
                continue
            }
            val buf = codec.getInputBuffer(idx)!!
            buf.clear()
            var n = minOf(pcm.size - pos, buf.remaining())
            n -= n % frameBytes
            buf.put(pcm, pos, n)
            val pts = (offsetFrames + pos / frameBytes) * 1_000_000L / sampleRate
            lastAudioUs = pts
            codec.queueInputBuffer(idx, 0, n, pts, 0)
            pos += n
            drain(codec, false)
        }
    }

    private fun drain(codec: MediaCodec, endOfStream: Boolean) {
        var waits = 0
        while (true) {
            val idx = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++waits > 300) return
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val track = muxer.addTrack(codec.outputFormat)
                    if (codec === video) videoTrack = track else audioTrack = track
                    maybeStart()
                }
                idx >= 0 -> {
                    val out = codec.getOutputBuffer(idx)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0) {
                        out.position(info.offset)
                        out.limit(info.offset + info.size)
                        val track = if (codec === video) videoTrack else audioTrack
                        if (started) {
                            muxer.writeSampleData(track, out, info)
                        } else {
                            val copy = ByteBuffer.allocate(info.size)
                            copy.put(out)
                            copy.flip()
                            val i = MediaCodec.BufferInfo()
                            i.set(0, info.size, info.presentationTimeUs, info.flags)
                            pending.add(Pending(track, copy, i))
                        }
                    }
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(idx, false)
                    if (eos) return
                }
            }
        }
    }

    private fun maybeStart() {
        if (started || videoTrack < 0 || (hasAudio && audioTrack < 0)) return
        muxer.start()
        started = true
        for (p in pending) muxer.writeSampleData(p.track, p.data, p.info)
        pending.clear()
    }

    private fun endStream(codec: MediaCodec, pts: Long) {
        var idx: Int
        while (true) {
            idx = codec.dequeueInputBuffer(10_000)
            if (idx >= 0) break
            drain(codec, false)
        }
        codec.queueInputBuffer(idx, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(codec, true)
    }

    fun finish() {
        try {
            endStream(video, lastVideoUs + 1_000_000L / fps)
            audio?.let { endStream(it, lastAudioUs + 1) }
            if (!started) throw IllegalStateException("The encoder produced no video")
            muxer.stop()
            started = false
        } finally {
            release()
        }
    }

    fun release() {
        try { video.stop() } catch (_: Throwable) {}
        try { video.release() } catch (_: Throwable) {}
        try { audio?.stop() } catch (_: Throwable) {}
        try { audio?.release() } catch (_: Throwable) {}
        try { if (started) muxer.stop() } catch (_: Throwable) {}
        started = false
        try { muxer.release() } catch (_: Throwable) {}
    }
}
