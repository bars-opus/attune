package com.barsopus.attune

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.telephony.TelephonyManager
import android.view.WindowManager
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.model.AgeRangeSource
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

    override fun onCreate(savedInstanceState: Bundle?) {
        // A share (Together Phase 8b) is handled once. When Android brings
        // Attune back after reclaiming it, or it's reopened from Recents, the
        // original share intent would otherwise be delivered again.
        val restored = savedInstanceState != null ||
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (restored && intent.action == Intent.ACTION_SEND) {
            intent = Intent(Intent.ACTION_MAIN)
        }
        super.onCreate(savedInstanceState)
        disableMapboxTelemetry()
    }

    // The couple map sends Mapbox no usage events (spec 2026-10-16 §6.3).
    // com.mapbox.common is an `implementation` dependency of the Mapbox
    // plugin, so the app can't compile against it; its public
    // TelemetryUtils.setEventsCollectionState(false, null) is called by
    // name instead, which keeps the version tied to the plugin's.
    private fun disableMapboxTelemetry() {
        try {
            val utils = Class.forName("com.mapbox.common.TelemetryUtils")
            val callback = Class.forName("com.mapbox.common.TelemetryUtilsResponseCallback")
            utils.getMethod(
                "setEventsCollectionState",
                Boolean::class.javaPrimitiveType,
                callback,
            ).invoke(null, false, null)
        } catch (_: Throwable) {
            // No Mapbox in this build, or the API moved: nothing to send.
        }
    }

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

        // Spec 1 W2b (§3.3 A3): the SIM's country, for the phone step's
        // default. Needs no permission; nothing is stored or sent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "simCountryIso" -> {
                        val telephony =
                            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                        val iso = telephony?.simCountryIso
                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    // Spec 2 W8b (§2.3): the network's country, for Dating's
                    // device check (the place, never stored by the phone).
                    "networkCountryIso" -> {
                        val telephony =
                            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                        val iso = telephony?.networkCountryIso
                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // Spec 1 W6b (§3.3 A2): Play Age Signals, once, at A2. Only a status
        // goes back (adult, minor, supervised, unknown, unavailable); nothing
        // is stored or sent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/age_signals")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> readAgeSignal(result)
                    else -> result.notImplemented()
                }
            }

        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. Nothing is logged or sent.
        // Reply first: once the activity finishes the engine may be gone.
        // Spec 2 W8a (§6.7): setSecure(bool) puts FLAG_SECURE on the window
        // while any Dating page is open (screenshots, screen recording and
        // the Recents thumbnail come out blank) and takes it off after the
        // last one; it answers false (Android never reports a capture).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/safety")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishAndRemoveTask" -> {
                        result.success(null)
                        finishAndRemoveTask()
                    }
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(false)
                    }
                    // Spec 2 W8b (§6.7): the app icon is the launcher alias
                    // that is on; nothing else is stored. The new one is on
                    // before the old one goes off (never no launcher entry).
                    // DONT_KILL_APP keeps the process, but Android may
                    // still close the task started from the alias that went
                    // off; the page says so before the choice, and the next
                    // open starts afresh (a new engine: nothing Dating was
                    // showing is kept; the Dating lock, if on, asks again).
                    "appIcon" -> result.success(if (aliasOn(plainIcon)) "plain" else "default")
                    "setAppIcon" -> {
                        val plain = call.arguments == "plain"
                        try {
                            setAlias(if (plain) plainIcon else defaultIcon, true)
                            setAlias(if (plain) defaultIcon else plainIcon, false)
                            result.success(true)
                        } catch (_: Throwable) {
                            // Undo a half-done switch the same way round
                            // (old on first): never two icons, never none.
                            try {
                                setAlias(if (plain) defaultIcon else plainIcon, true)
                                setAlias(if (plain) plainIcon else defaultIcon, false)
                            } catch (_: Throwable) {
                            }
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Spec 2 W8b (§6.7): the two launcher aliases (AndroidManifest.xml).
    // Never rename them: the phone keeps each one's on/off by its name.
    private val defaultIcon get() = ComponentName(this, "com.barsopus.attune.IconDefault")
    private val plainIcon get() = ComponentName(this, "com.barsopus.attune.IconPlain")

    private fun aliasOn(alias: ComponentName): Boolean =
        when (packageManager.getComponentEnabledSetting(alias)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            // As the manifest says: only the default is on.
            else -> alias == defaultIcon
        }

    private fun setAlias(alias: ComponentName, on: Boolean) {
        packageManager.setComponentEnabledSetting(
            alias,
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    // 18 and over is adult; a band that ends under 18 is supervised when a
    // parent set it (TIER_B), otherwise minor; not shared is unknown; any
    // failure (no Play Store, an old one, not installed from Play) is
    // unavailable, and the date of birth decides.
    private fun readAgeSignal(result: MethodChannel.Result) {
        try {
            AgeSignalsManagerFactory.create(applicationContext)
                .checkAgeSignals(AgeSignalsRequest.builder().build())
                .addOnSuccessListener { signal ->
                    val lower = signal.ageLower()
                    val upper = signal.ageUpper()
                    val status = when {
                        lower != null && lower >= 18 -> "adult"
                        upper != null && upper < 18 ->
                            if (signal.ageRangeSource() == AgeRangeSource.TIER_B) "supervised" else "minor"
                        else -> "unknown"
                    }
                    result.success(mapOf("status" to status))
                }
                .addOnFailureListener { result.success(mapOf("status" to "unavailable")) }
        } catch (_: Throwable) {
            result.success(mapOf("status" to "unavailable"))
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
