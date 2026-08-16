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

    // MediaStore commonly fires ContentObserver.onChange more than once for
    // a single screenshot write (e.g. once for the initial pending/zero-byte
    // row insert, again when the file write completes/metadata updates).
    // This window suppresses re-firing "onScreenshot" for the same physical
    // screenshot. 2s is comfortably longer than the gap between those two
    // MediaStore callbacks (typically well under a second on-device) while
    // remaining short enough that two genuinely distinct screenshots taken
    // in quick succession (a realistic user action — e.g. screenshotting two
    // parts of a conversation back to back) still both get reported.
    private val screenshotDebounceMillis = 2000L
    private var methodChannel: MethodChannel? = null
    private var screenshotObserver: ContentObserver? = null

    // Only ever read/written from onChange, which — because the observer
    // below is constructed with Handler(Looper.getMainLooper()) — always
    // runs on the main thread. No additional synchronization is needed.
    private var lastScreenshotDetectedAtMillis: Long = 0L

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

        // Reset so a stale timestamp from a previous viewing session can't
        // suppress the first genuine detection of this new session.
        lastScreenshotDetectedAtMillis = 0L

        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (uri == null) return
                if (!isLikelyScreenshot(uri)) return

                val now = System.currentTimeMillis()
                if (now - lastScreenshotDetectedAtMillis < screenshotDebounceMillis) {
                    // Almost certainly a second MediaStore callback for the
                    // same screenshot write (pending-row insert followed by
                    // completed-write update) — swallow it.
                    return
                }
                lastScreenshotDetectedAtMillis = now
                methodChannel?.invokeMethod("onScreenshot", null)
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
