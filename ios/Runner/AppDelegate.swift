import AVFAudio
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Best-effort screenshot detection for ephemeral video viewing (see
  // lib/core/services/media/screenshot_detection_service.dart). iOS has a
  // genuine, reliable system notification for this — UIApplication's own
  // userDidTakeScreenshotNotification — unlike Android, which has no
  // equivalent API and falls back to a ContentObserver heuristic instead.
  // This channel/observer is only ever armed while
  // EphemeralVideoViewerScreen is on screen (startDetection/stopDetection
  // are called from that screen's initState/dispose), so there is no
  // always-on screenshot surveillance anywhere else in the app.
  private var screenshotChannel: FlutterMethodChannel?
  private var screenshotObserver: NSObjectProtocol?
  private var recordingHapticsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let channel = FlutterMethodChannel(
      name: "attune/screenshot_detection",
      binaryMessenger: controller.binaryMessenger
    )
    screenshotChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startDetection":
        self?.startScreenshotDetection()
        result(nil)
      case "stopDetection":
        self?.stopScreenshotDetection()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let hapticsChannel = FlutterMethodChannel(
      name: "attune/recording_haptics",
      binaryMessenger: controller.binaryMessenger
    )
    recordingHapticsChannel = hapticsChannel
    hapticsChannel.setMethodCallHandler { call, result in
      guard call.method == "setEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let enabled = call.arguments as? Bool else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "setEnabled expects a boolean",
          details: nil
        ))
        return
      }

      guard #available(iOS 13.0, *) else {
        result(nil)
        return
      }
      do {
        try AVAudioSession.sharedInstance()
          .setAllowHapticsAndSystemSoundsDuringRecording(enabled)
        result(nil)
      } catch {
        result(FlutterError(
          code: "AUDIO_SESSION_ERROR",
          message: "Could not configure recording haptics",
          details: error.localizedDescription
        ))
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startScreenshotDetection() {
    // Avoid stacking duplicate observers if startDetection is called twice
    // without an intervening stopDetection.
    stopScreenshotDetection()
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenshotChannel?.invokeMethod("onScreenshot", arguments: nil)
    }
  }

  private func stopScreenshotDetection() {
    if let observer = screenshotObserver {
      NotificationCenter.default.removeObserver(observer)
      screenshotObserver = nil
    }
  }
}
