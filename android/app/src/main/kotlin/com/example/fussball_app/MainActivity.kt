package com.example.fussball_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraConstrainedHighSpeedCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.net.wifi.WifiManager
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.max

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
                    "getLastFps" -> {
                        result.success(motionDetector.getLastFps())
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
    companion object {
        private const val TAG = "FussballMotion"
        private const val TARGET_WIDTH = 1280
        private const val TARGET_HEIGHT = 720
        private const val TARGET_FPS = 120
        private const val AE_WARMUP_MS = 500L
        private const val ROI_RATIO = 0.03f
    }

    private var threshold: Double = 0.22

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraDevice: CameraDevice? = null
    private var highSpeedSession: CameraConstrainedHighSpeedCaptureSession? = null
    private var previewSurfaceTexture: SurfaceTexture? = null
    private var previewSurface: Surface? = null
    private var glAnalyzer: GlRoiAnalyzer? = null
    private var selectedSize: Size = Size(TARGET_WIDTH, TARGET_HEIGHT)
    private var selectedFpsRange: Range<Int> = Range(TARGET_FPS, TARGET_FPS)

    private var running = false
    private var lastTriggerTimestampNs: Long = 0L

    private var lastFps: Double = 0.0

    private var aeLockRunnable: Runnable? = null

    fun setThreshold(value: Double) {
        threshold = value.coerceIn(0.02, 0.9)
    }

    fun getLastFps(): Double = lastFps

    fun startMonitoring() {
        if (running) {
            return
        }

        running = true
        lastTriggerTimestampNs = 0L
        lastFps = 0.0

        startBackgroundThread()
        // Execute camera and EGL initialization entirely on the background thread
        backgroundHandler?.post {
            openCamera()
        }
    }

    fun stopMonitoring() {
        running = false

        val handler = backgroundHandler
        if (handler != null) {
            // Ensure GLES resources are released on the correct thread
            handler.post {
                clearAeLockTimer()
                closeCamera()
            }
        } else {
            clearAeLockTimer()
            closeCamera()
        }

        // stopBackgroundThread will wait for the posted tasks to finish via quitSafely
        stopBackgroundThread()

        lastTriggerTimestampNs = 0L
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
        val cameraId = pickRearCameraId(manager) ?: return
        val cameraCharacteristics = manager.getCameraCharacteristics(cameraId)
        val streamMap = cameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: run {
            Log.e(TAG, "No stream configuration map available for camera $cameraId")
            return
        }
        val config = selectHighSpeedConfig(streamMap)
        if (config == null) {
            Log.e(TAG, "No valid constrained high-speed size/range pair available")
            return
        }
        selectedSize = config.size
        selectedFpsRange = config.fpsRange

        Log.i(
            TAG,
            "Opening cameraId=$cameraId highSpeedSize=${selectedSize.width}x${selectedSize.height} " +
                "requestedFps=$TARGET_FPS selectedRange=$selectedFpsRange"
        )

        setupGlAnalyzer(selectedSize.width, selectedSize.height)

        if (glAnalyzer?.externalTextureId == 0) {
            Log.e(TAG, "GL Analyzer externalTextureId is 0, aborting camera open")
            return
        }

        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "Camera permission missing, cannot start motion detector")
            return
        }

        try {
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (!running) {
                        device.close()
                        return
                    }
                    Log.i(TAG, "Camera opened: id=${device.id}")
                    cameraDevice = device
                    createHighSpeedSession(device)
                }

                override fun onDisconnected(device: CameraDevice) {
                    Log.w(TAG, "Camera disconnected: id=${device.id}")
                    device.close()
                    cameraDevice = null
                }

                override fun onError(device: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera error: id=${device.id} error=$error")
                    device.close()
                    cameraDevice = null
                }
            }, backgroundHandler)
        } catch (error: Throwable) {
            Log.e(TAG, "openCamera failed", error)
            closeCamera()
        }
    }

    private fun createHighSpeedSession(device: CameraDevice) {
        if (cameraDevice == null) {
            Log.e(TAG, "Camera device is null, cannot create high-speed session")
            return
        }
        val surface = previewSurface ?: run {
            Log.e(TAG, "Preview surface missing, cannot create high-speed session")
            return
        }
        try {
            Log.i(TAG, "Creating constrained high-speed session")
            device.createConstrainedHighSpeedCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (!running) {
                            session.close()
                            return
                        }

                        val highSpeed = session as? CameraConstrainedHighSpeedCaptureSession
                        if (highSpeed == null) {
                            Log.e(TAG, "Configured session is not high-speed")
                            closeCamera()
                            return
                        }
                        highSpeedSession = highSpeed
                        Log.i(TAG, "Constrained high-speed session configured")
                        applyRepeatingRequest(aeLocked = false)
                        scheduleAeLockAfterWarmup()
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "Constrained high-speed session configure failed")
                        session.close()
                    }
                },
                backgroundHandler
            )
        } catch (error: Throwable) {
            Log.e(TAG, "createHighSpeedSession failed", error)
            closeCamera()
        }
    }

    private fun applyRepeatingRequest(aeLocked: Boolean) {
        val device = cameraDevice ?: return
        val session = highSpeedSession ?: return
        val surface = previewSurface ?: return

        try {
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(surface)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, selectedFpsRange)
                set(CaptureRequest.CONTROL_AE_LOCK, aeLocked)
            }

            val requestList = session.createHighSpeedRequestList(builder.build())
            try {
                session.setRepeatingBurst(requestList, null, backgroundHandler)
                Log.i(
                    TAG,
                    "Repeating high-speed burst started, aeLocked=$aeLocked fpsRange=$selectedFpsRange size=${selectedSize.width}x${selectedSize.height}"
                )
            } catch (e: IllegalStateException) {
                Log.w(TAG, "Hardware overload: setRepeatingBurst threw IllegalStateException", e)
            }
        } catch (error: Throwable) {
            Log.e(TAG, "applyRepeatingRequest failed (aeLocked=$aeLocked range=$selectedFpsRange)", error)
            closeCamera()
        }
    }

    private fun scheduleAeLockAfterWarmup() {
        clearAeLockTimer()

        val handler = backgroundHandler ?: return
        aeLockRunnable = Runnable {
            if (running) {
                Log.i(TAG, "Applying AE lock after warmup")
                applyRepeatingRequest(aeLocked = true)
            }
        }
        handler.postDelayed(aeLockRunnable!!, AE_WARMUP_MS)
    }

    private fun clearAeLockTimer() {
        val handler = backgroundHandler
        val runnable = aeLockRunnable
        if (handler != null && runnable != null) {
            handler.removeCallbacks(runnable)
        }
        aeLockRunnable = null
    }

    private fun closeCamera() {
        clearAeLockTimer()

        try {
            highSpeedSession?.stopRepeating()
        } catch (_: Throwable) {
            // Ignore.
        }

        try {
            highSpeedSession?.close()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            highSpeedSession = null
        }

        try {
            cameraDevice?.close()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            cameraDevice = null
        }

        try {
            previewSurface?.release()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            previewSurface = null
        }

        try {
            previewSurfaceTexture?.release()
        } catch (_: Throwable) {
            // Ignore.
        } finally {
            previewSurfaceTexture = null
        }

        glAnalyzer?.release()
        glAnalyzer = null

        Log.i(TAG, "Camera resources closed")
    }

    private fun pickRearCameraId(manager: CameraManager): String? {
        val cameraIds = manager.cameraIdList
        for (id in cameraIds) {
            val characteristics = manager.getCameraCharacteristics(id)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                return id
            }
        }
        return null
    }

    private fun selectFpsRange(availableRanges: List<Range<Int>>): Range<Int> {
        if (availableRanges.isEmpty()) {
            return Range(TARGET_FPS, TARGET_FPS)
        }

        val fixedRanges = availableRanges.filter { it.lower == it.upper }
        val exact = fixedRanges.firstOrNull { it.lower == TARGET_FPS && it.upper == TARGET_FPS }
        if (exact != null) {
            return exact
        }

        val supportingTarget = fixedRanges
            .filter { it.upper >= TARGET_FPS }
            .sortedWith(compareByDescending<Range<Int>> { it.upper }.thenByDescending { it.lower })
        if (supportingTarget.isNotEmpty()) {
            return supportingTarget.first()
        }

        return fixedRanges
            .sortedWith(compareByDescending<Range<Int>> { it.upper }.thenByDescending { it.lower })
            .firstOrNull()
            ?: availableRanges.sortedWith(compareByDescending<Range<Int>> { it.upper }.thenByDescending { it.lower }).first()
    }

    private fun selectHighSpeedConfig(streamMap: android.hardware.camera2.params.StreamConfigurationMap): HighSpeedConfig? {
        val sizes = streamMap.highSpeedVideoSizes?.toList().orEmpty()
        if (sizes.isEmpty()) {
            return null
        }

        val configs = mutableListOf<HighSpeedConfig>()
        for (size in sizes) {
            val ranges = try {
                streamMap.getHighSpeedVideoFpsRangesFor(size).toList()
            } catch (_: Throwable) {
                emptyList()
            }
            val fixed = ranges.filter { it.lower == it.upper }
            if (fixed.isEmpty()) {
                continue
            }
            val selected = selectFpsRange(fixed)
            configs += HighSpeedConfig(size = size, fpsRange = selected)
        }

        if (configs.isEmpty()) {
            return null
        }

        val exact720p120 = configs.firstOrNull {
            it.size.width == TARGET_WIDTH &&
                it.size.height == TARGET_HEIGHT &&
                it.fpsRange.lower == TARGET_FPS &&
                it.fpsRange.upper == TARGET_FPS
        }
        if (exact720p120 != null) {
            return exact720p120
        }

        val best720p = configs
            .filter { it.size.width == TARGET_WIDTH && it.size.height == TARGET_HEIGHT }
            .maxByOrNull { it.fpsRange.upper }
        if (best720p != null) {
            return best720p
        }

        return configs.maxWithOrNull(
            compareBy<HighSpeedConfig> { it.fpsRange.upper }
                .thenBy { it.fpsRange.lower }
                .thenBy { it.size.width * it.size.height }
        )
    }

    private fun setupGlAnalyzer(width: Int, height: Int) {
        val handler = backgroundHandler ?: return
        val analyzer = GlRoiAnalyzer(
            targetWidth = width,
            targetHeight = height,
            onAnalyzedFrame = { frame ->
                if (!running) {
                    return@GlRoiAnalyzer
                }
                lastFps = frame.fps
                if (frame.motionScore >= threshold && (frame.timestampNs - lastTriggerTimestampNs) >= 300_000_000L) {
                    lastTriggerTimestampNs = frame.timestampNs
                    Log.i(TAG, "Motion trigger emitted: score=${frame.motionScore} threshold=$threshold tsNs=${frame.timestampNs}")
                    emitEvent(
                        mapOf(
                            "type" to "motion",
                            "motionScore" to frame.motionScore,
                            "sensorTimestampNs" to frame.timestampNs,
                        )
                    )
                }
            }
        )
        analyzer.initialize()
        glAnalyzer = analyzer

        val surfaceTexture = SurfaceTexture(analyzer.externalTextureId)
        surfaceTexture.setDefaultBufferSize(width, height)
        surfaceTexture.setOnFrameAvailableListener({ analyzer.consumeFrame(surfaceTexture) }, handler)
        previewSurfaceTexture = surfaceTexture
        previewSurface = Surface(surfaceTexture)
    }
}

private data class HighSpeedConfig(
    val size: Size,
    val fpsRange: Range<Int>,
)

private data class AnalyzedFrame(
    val timestampNs: Long,
    val motionScore: Double,
    val fps: Double,
)

private class GlRoiAnalyzer(
    private val targetWidth: Int,
    private val targetHeight: Int,
    private val onAnalyzedFrame: (AnalyzedFrame) -> Unit,
) {
    companion object {
        private const val TAG = "FussballMotion"
        private const val ROI_RATIO = 0.03f
        private const val SAMPLE_WIDTH = 160
        private const val SAMPLE_HEIGHT = 90
    }

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var surface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var program = 0
    private var frameBuffer = 0
    private var colorTexture = 0

    private var positionHandle = -1
    private var texCoordHandle = -1
    private var textureHandle = -1

    private var previousRoi: ByteArray? = null
    private var lastTimestampNs: Long = 0L
    private var fpsWindowStartNs: Long = 0L
    private var fpsFrameCount = 0
    private var lastFps = 0.0

    private val vertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 4 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(
                floatArrayOf(
                    -1f, -1f, 0f, 1f,
                    1f, -1f, 1f, 1f,
                    -1f, 1f, 0f, 0f,
                    1f, 1f, 1f, 0f,
                )
            )
            position(0)
        }

    val externalTextureId: Int
        get() = externalTexture

    private var externalTexture = 0

    fun initialize() {
        setupEgl()
        externalTexture = createExternalTexture()
        colorTexture = create2DTexture(SAMPLE_WIDTH, SAMPLE_HEIGHT)
        frameBuffer = createFrameBuffer(colorTexture)
        program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        texCoordHandle = GLES20.glGetAttribLocation(program, "aTexCoord")
        textureHandle = GLES20.glGetUniformLocation(program, "uTexture")
    }

    fun consumeFrame(surfaceTexture: SurfaceTexture) {
        if (display == EGL14.EGL_NO_DISPLAY) {
            return
        }

        makeCurrent()
        surfaceTexture.updateTexImage()
        val timestampNs = surfaceTexture.timestamp
        if (timestampNs <= 0L || timestampNs == lastTimestampNs) {
            return
        }
        lastTimestampNs = timestampNs

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, frameBuffer)
        GLES20.glViewport(0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT)
        GLES20.glUseProgram(program)

        vertexBuffer.position(0)
        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(positionHandle)
        vertexBuffer.position(2)
        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(texCoordHandle)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, externalTexture)
        GLES20.glUniform1i(textureHandle, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        val roi = readCenterRoiLuma()
        val motionScore = computeMotionScore(roi)
        updateFps(timestampNs)
        onAnalyzedFrame(AnalyzedFrame(timestampNs = timestampNs, motionScore = motionScore, fps = lastFps))
    }

    fun release() {
        if (display == EGL14.EGL_NO_DISPLAY) {
            return
        }

        EGL14.eglMakeCurrent(display, surface, surface, context)
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
        if (frameBuffer != 0) {
            GLES20.glDeleteFramebuffers(1, intArrayOf(frameBuffer), 0)
            frameBuffer = 0
        }
        if (colorTexture != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(colorTexture), 0)
            colorTexture = 0
        }
        if (externalTexture != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(externalTexture), 0)
            externalTexture = 0
        }

        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display, surface)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
        display = EGL14.EGL_NO_DISPLAY
        context = EGL14.EGL_NO_CONTEXT
        surface = EGL14.EGL_NO_SURFACE
        previousRoi = null
    }

    private fun setupEgl() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) {
            throw IllegalStateException("Unable to get EGL display")
        }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "Unable to initialize EGL" }

        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(EGL14.eglChooseConfig(display, attribList, 0, configs, 0, 1, numConfigs, 0)) {
            "Unable to choose EGL config"
        }
        val config = configs[0] ?: throw IllegalStateException("No EGL config")

        context = EGL14.eglCreateContext(
            display,
            config,
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0
        )
        check(context != EGL14.EGL_NO_CONTEXT) { "Unable to create EGL context" }

        surface = EGL14.eglCreatePbufferSurface(
            display,
            config,
            intArrayOf(EGL14.EGL_WIDTH, SAMPLE_WIDTH, EGL14.EGL_HEIGHT, SAMPLE_HEIGHT, EGL14.EGL_NONE),
            0
        )
        check(surface != EGL14.EGL_NO_SURFACE) { "Unable to create EGL pbuffer surface" }
        makeCurrent(isInitializing = true)
    }

    private fun makeCurrent(isInitializing: Boolean = false) {
        if (!EGL14.eglMakeCurrent(display, surface, surface, context)) {
            if (isInitializing) {
                throw IllegalStateException("eglMakeCurrent failed during setup")
            }
            Log.w(TAG, "eglMakeCurrent failed, rebuilding entire EGL context")
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            if (display != EGL14.EGL_NO_DISPLAY) EGL14.eglTerminate(display)

            display = EGL14.EGL_NO_DISPLAY
            context = EGL14.EGL_NO_CONTEXT
            surface = EGL14.EGL_NO_SURFACE

            initialize()
        }
    }

    private fun createExternalTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val texture = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        return texture
    }

    private fun create2DTexture(width: Int, height: Int): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val texture = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            width,
            height,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            null
        )
        return texture
    }

    private fun createFrameBuffer(textureId: Int): Int {
        val frameBuffers = IntArray(1)
        GLES20.glGenFramebuffers(1, frameBuffers, 0)
        val fbo = frameBuffers[0]
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo)
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER,
            GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D,
            textureId,
            0
        )
        if (GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            throw IllegalStateException("Framebuffer incomplete")
        }
        return fbo
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)
        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            val info = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw IllegalStateException("Program link failed: $info")
        }
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        return program
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val compileStatus = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0)
        if (compileStatus[0] == 0) {
            val info = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw IllegalStateException("Shader compile failed: $info")
        }
        return shader
    }

    private fun readCenterRoiLuma(): ByteArray {
        val roiWidth = max(1, (SAMPLE_WIDTH * ROI_RATIO).toInt())
        val roiHeight = max(1, (SAMPLE_HEIGHT * ROI_RATIO).toInt())
        val startX = (SAMPLE_WIDTH - roiWidth) / 2
        val startY = (SAMPLE_HEIGHT - roiHeight) / 2

        val pixelBuffer = ByteBuffer.allocateDirect(roiWidth * roiHeight * 4)
        GLES20.glReadPixels(
            startX,
            startY,
            roiWidth,
            roiHeight,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            pixelBuffer
        )

        val roi = ByteArray(roiWidth * roiHeight)
        for (i in roi.indices) {
            roi[i] = pixelBuffer.get(i * 4)
        }
        return roi
    }

    private fun computeMotionScore(currentRoi: ByteArray): Double {
        val previous = previousRoi
        previousRoi = currentRoi
        if (previous == null || previous.size != currentRoi.size) {
            return 0.0
        }

        var diffSum = 0L
        for (i in currentRoi.indices) {
            val currentValue = currentRoi[i].toInt() and 0xFF
            val previousValue = previous[i].toInt() and 0xFF
            diffSum += kotlin.math.abs(currentValue - previousValue)
        }
        return diffSum.toDouble() / (currentRoi.size.toDouble() * 255.0)
    }

    private fun updateFps(timestampNs: Long) {
        if (fpsWindowStartNs == 0L) {
            fpsWindowStartNs = timestampNs
            fpsFrameCount = 0
        }
        fpsFrameCount += 1
        val elapsed = timestampNs - fpsWindowStartNs
        if (elapsed < 500_000_000L) {
            return
        }
        lastFps = fpsFrameCount.toDouble() * 1_000_000_000.0 / elapsed.toDouble()
        fpsWindowStartNs = timestampNs
        fpsFrameCount = 0
        Log.d(TAG, "Measured analyzer FPS=${"%.2f".format(lastFps)}")
    }

    private val VERTEX_SHADER = """
        attribute vec2 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = vec4(aPosition, 0.0, 1.0);
            vTexCoord = aTexCoord;
        }
    """.trimIndent()

    private val FRAGMENT_SHADER = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 vTexCoord;
        uniform samplerExternalOES uTexture;
        void main() {
            vec3 rgb = texture2D(uTexture, vTexCoord).rgb;
            float y = dot(rgb, vec3(0.299, 0.587, 0.114));
            gl_FragColor = vec4(y, y, y, 1.0);
        }
    """.trimIndent()
}
