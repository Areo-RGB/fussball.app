package com.example.fussball_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Range
import android.util.Size
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val identityChannel = "fussball/device_identity"
    private val performanceChannel = "fussball/performance_mode"
    private val clockChannel = "fussball/clock"
    private val motionMethodChannel = "fussball/motion_detection"
    private val motionEventChannel = "fussball/motion_events"

    private var wifiLock: WifiManager.WifiLock? = null
    private var cpuWakeLock: PowerManager.WakeLock? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var motionEventSink: EventChannel.EventSink? = null
    private lateinit var motionDetector: NativeMotionDetector

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        motionDetector = NativeMotionDetector(
            context = this,
            emitEvent = { payload ->
                mainHandler.post {
                    motionEventSink?.success(payload)
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, identityChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getDeviceIdentity") {
                    val androidId = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID
                    ) ?: "unknown_android_id"

                    val payload = mapOf(
                        "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
                        "model" to (Build.MODEL ?: "unknown"),
                        "device" to (Build.DEVICE ?: "unknown"),
                        "androidId" to androidId
                    )
                    result.success(payload)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, performanceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableHighPerformanceMode" -> {
                        enableHighPerformanceMode()
                        result.success(true)
                    }
                    "disableHighPerformanceMode" -> {
                        disableHighPerformanceMode()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, clockChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getElapsedRealtimeNanos") {
                    result.success(SystemClock.elapsedRealtimeNanos())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, motionMethodChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMonitoring" -> {
                        val threshold = (call.argument<Double>("threshold") ?: 0.22)
                        motionDetector.setThreshold(threshold)
                        motionDetector.startMonitoring()
                        result.success(true)
                    }
                    "stopMonitoring" -> {
                        motionDetector.stopMonitoring()
                        result.success(true)
                    }
                    "setThreshold" -> {
                        val threshold = (call.argument<Double>("threshold") ?: 0.22)
                        motionDetector.setThreshold(threshold)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, motionEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    motionEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    motionEventSink = null
                }
            })
    }

    private fun enableHighPerformanceMode() {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock?.isHeld != true) {
                val lockMode = WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wifiManager.createWifiLock(lockMode, "fussball:high_perf_wifi").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (_: Throwable) {
            // Best-effort for personal project.
        }

        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (cpuWakeLock?.isHeld != true) {
                cpuWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "fussball:high_perf_cpu"
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (_: Throwable) {
            // Best-effort for personal project.
        }

        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun disableHighPerformanceMode() {
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            wifiLock = null
        }

        try {
            if (cpuWakeLock?.isHeld == true) {
                cpuWakeLock?.release()
            }
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            cpuWakeLock = null
        }

        runOnUiThread {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onDestroy() {
        motionDetector.stopMonitoring()
        disableHighPerformanceMode()
        super.onDestroy()
    }
}

private class NativeMotionDetector(
    private val context: Context,
    private val emitEvent: (Map<String, Any>) -> Unit
) {
    private var threshold: Double = 0.22

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null

    private var running = false
    private var cameraId: String? = null

    private var previousRoi: ByteArray? = null
    private var lastTriggerTimestampNs: Long = 0L

    private var fpsWindowStartNs: Long = 0L
    private var fpsFrameCount: Int = 0
    private var lastFps: Double = 0.0

    fun setThreshold(value: Double) {
        threshold = value.coerceIn(0.02, 0.9)
    }

    fun startMonitoring() {
        if (running) {
            return
        }
        running = true
        previousRoi = null
        lastTriggerTimestampNs = 0L
        fpsWindowStartNs = 0L
        fpsFrameCount = 0
        lastFps = 0.0

        startBackgroundThread()
        openCamera()
    }

    fun stopMonitoring() {
        running = false
        closeCamera()
        stopBackgroundThread()
        previousRoi = null
        lastTriggerTimestampNs = 0L
        fpsWindowStartNs = 0L
        fpsFrameCount = 0
        lastFps = 0.0
    }

    private fun startBackgroundThread() {
        if (backgroundThread != null) {
            return
        }

        backgroundThread = HandlerThread("fussball-camera-thread").also { thread ->
            thread.start()
            backgroundHandler = Handler(thread.looper)
        }
    }

    private fun stopBackgroundThread() {
        val thread = backgroundThread ?: return
        thread.quitSafely()
        try {
            thread.join()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        backgroundThread = null
        backgroundHandler = null
    }

    private fun openCamera() {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraInfo = pickRearCamera(manager) ?: return
        cameraId = cameraInfo.id

        val imageReader = ImageReader.newInstance(
            cameraInfo.size.width,
            cameraInfo.size.height,
            ImageFormat.YUV_420_888,
            2
        )
        imageReader.setOnImageAvailableListener({ reader ->
            processImage(reader.acquireLatestImage())
        }, backgroundHandler)
        this.imageReader = imageReader

        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        try {
            manager.openCamera(cameraInfo.id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (!running) {
                        device.close()
                        return
                    }
                    cameraDevice = device
                    createCaptureSession(device, imageReader, cameraInfo.fpsRange)
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    cameraDevice = null
                }

                override fun onError(device: CameraDevice, error: Int) {
                    device.close()
                    cameraDevice = null
                }
            }, backgroundHandler)
        } catch (_: Throwable) {
            closeCamera()
        }
    }

    private fun createCaptureSession(
        device: CameraDevice,
        reader: ImageReader,
        fpsRange: Range<Int>?
    ) {
        try {
            val requestBuilder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(reader.surface)
                fpsRange?.let {
                    set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it)
                }
            }

            device.createCaptureSession(
                listOf(reader.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (!running) {
                            session.close()
                            return
                        }
                        captureSession = session
                        try {
                            session.setRepeatingRequest(requestBuilder.build(), null, backgroundHandler)
                        } catch (_: Throwable) {
                            closeCamera()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        session.close()
                    }
                },
                backgroundHandler
            )
        } catch (_: Throwable) {
            closeCamera()
        }
    }

    private fun closeCamera() {
        try {
            captureSession?.stopRepeating()
        } catch (_: Throwable) {
            // Ignore.
        }

        try {
            captureSession?.close()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            captureSession = null
        }

        try {
            cameraDevice?.close()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            cameraDevice = null
        }

        try {
            imageReader?.close()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            imageReader = null
        }
    }

    private fun processImage(image: Image?) {
        if (image == null) {
            return
        }

        try {
            if (!running) {
                return
            }

            val roi = extractCenterRoiLuma(image)
            val previous = previousRoi

            val motionScore = if (previous == null || previous.size != roi.size) {
                0.0
            } else {
                var diffSum = 0L
                for (index in roi.indices) {
                    val currentValue = roi[index].toInt() and 0xFF
                    val previousValue = previous[index].toInt() and 0xFF
                    diffSum += abs(currentValue - previousValue)
                }
                diffSum.toDouble() / (roi.size.toDouble() * 255.0)
            }

            previousRoi = roi

            val timestampNs = image.timestamp
            updateAndEmitFps(timestampNs)

            if (motionScore >= threshold && (timestampNs - lastTriggerTimestampNs) >= 300_000_000L) {
                lastTriggerTimestampNs = timestampNs
                emitEvent(
                    mapOf(
                        "type" to "motion",
                        "motionScore" to motionScore,
                        "sensorTimestampNs" to timestampNs,
                        "fps" to lastFps
                    )
                )
            }
        } finally {
            image.close()
        }
    }

    private fun updateAndEmitFps(frameTimestampNs: Long) {
        if (fpsWindowStartNs == 0L) {
            fpsWindowStartNs = frameTimestampNs
            fpsFrameCount = 0
        }

        fpsFrameCount += 1
        val elapsedNs = frameTimestampNs - fpsWindowStartNs
        if (elapsedNs < 1_000_000_000L) {
            return
        }

        val fps = fpsFrameCount.toDouble() * 1_000_000_000.0 / elapsedNs.toDouble()
        lastFps = fps
        emitEvent(
            mapOf(
                "type" to "fps",
                "fps" to fps
            )
        )

        fpsWindowStartNs = frameTimestampNs
        fpsFrameCount = 0
    }

    private fun extractCenterRoiLuma(image: Image): ByteArray {
        val width = image.width
        val height = image.height

        val roiWidth = max(1, (width * 0.03f).roundToInt())
        val roiHeight = max(1, (height * 0.03f).roundToInt())
        val startX = (width - roiWidth) / 2
        val startY = (height - roiHeight) / 2

        val yPlane = image.planes[0]
        val buffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride

        val roi = ByteArray(roiWidth * roiHeight)
        var cursor = 0

        for (y in 0 until roiHeight) {
            val rowBase = (startY + y) * rowStride + startX * pixelStride
            for (x in 0 until roiWidth) {
                val offset = rowBase + (x * pixelStride)
                roi[cursor++] = buffer.get(offset)
            }
        }

        return roi
    }

    private fun pickRearCamera(manager: CameraManager): CameraSelection? {
        val cameraIds = manager.cameraIdList
        for (id in cameraIds) {
            val characteristics = manager.getCameraCharacteristics(id)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing != CameraCharacteristics.LENS_FACING_BACK) {
                continue
            }

            val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?: continue
            val outputSizes = configMap.getOutputSizes(ImageFormat.YUV_420_888) ?: continue
            val selectedSize = pickLowResSize(outputSizes)
            val fpsRange = pickFpsRange(characteristics)
            return CameraSelection(id = id, size = selectedSize, fpsRange = fpsRange)
        }

        return null
    }

    private fun pickLowResSize(sizes: Array<Size>): Size {
        val sorted = sizes.sortedBy { it.width * it.height }
        val targetPixels = 320 * 240
        return sorted.firstOrNull { it.width * it.height >= targetPixels } ?: sorted.first()
    }

    private fun pickFpsRange(characteristics: CameraCharacteristics): Range<Int>? {
        val available = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            ?: return null

        val containingTarget = available
            .filter { it.lower <= 30 && it.upper >= 30 }
            .sortedWith(compareBy<Range<Int>> { it.upper - it.lower }.thenBy { abs(it.upper - 30) })
        if (containingTarget.isNotEmpty()) {
            return containingTarget.first()
        }

        return available.sortedBy { abs(it.upper - 30) }.firstOrNull()
    }

    private data class CameraSelection(
        val id: String,
        val size: Size,
        val fpsRange: Range<Int>?
    )
}
