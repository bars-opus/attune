package com.barsopus.attune

import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Best-effort screenshot detection for ephemeral video viewing (see
 * lib/core/services/media/screenshot_detection_service.dart). Unlike iOS,
 * Android has no dedicated "user took a screenshot" system API, so this
 * observes the shared-media ContentObserver for new rows under
 * MediaStore.Images.Media.EXTERNAL_CONTENT_URI whose path contains
 * "Screenshot" — a heuristic, not a guarantee: it can miss screenshots on
 * OEM launchers/gallery apps that store them elsewhere, and can (rarely)
 * false-positive on an image saved with "Screenshot" in its name. Shipped
 * anyway per the design spec's explicit "best-effort, acknowledged
 * unreliable" choice for this platform. The observer is only ever
 * registered while EphemeralVideoViewerScreen is on screen
 * (startDetection/stopDetection are called from that screen's
 * initState/dispose) — there is no always-on screenshot surveillance
 * anywhere else in the app.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "attune/screenshot_detection"
    private var methodChannel: MethodChannel? = null
    private var screenshotObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startDetection" -> {
                    startScreenshotDetection()
                    result.success(null)
                }
                "stopDetection" -> {
                    stopScreenshotDetection()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startScreenshotDetection() {
        // Avoid stacking duplicate observers if startDetection is called
        // twice without an intervening stopDetection.
        stopScreenshotDetection()

        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (uri == null) return
                if (isLikelyScreenshot(uri)) {
                    methodChannel?.invokeMethod("onScreenshot", null)
                }
            }
        }
        screenshotObserver = observer
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer,
        )
    }

    private fun isLikelyScreenshot(uri: Uri): Boolean {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val pathIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    val path = if (pathIndex >= 0) cursor.getString(pathIndex) else null
                    path?.contains("Screenshot", ignoreCase = true) == true
                } else {
                    false
                }
            } ?: false
        } catch (_: Exception) {
            // Best-effort only — any query failure (permission revoked,
            // provider gone, etc.) means "not detected," never a crash.
            false
        }
    }

    private fun stopScreenshotDetection() {
        screenshotObserver?.let { contentResolver.unregisterContentObserver(it) }
        screenshotObserver = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopScreenshotDetection()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
