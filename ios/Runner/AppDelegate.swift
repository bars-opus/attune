import AVFAudio
import DeclaredAgeRange
import Flutter
import StoreKit
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
  private var backupExclusionChannel: FlutterMethodChannel?
  private var ageSignalsChannel: FlutterMethodChannel?
  private var switcherCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The couple map sends Mapbox no usage events (spec 2026-10-16 §6.3).
    // MapboxMaps watches this default and passes it to
    // TelemetryUtils.setEventsCollectionState — the same switch its own
    // attribution menu's opt-out flips.
    UserDefaults.standard.set(false, forKey: "MGLMapboxMetricsEnabled")
    GeneratedPluginRegistrant.register(with: self)

    // Quick exit / privacy (Spec 2; research 06 §3 F3 (3)): a native cover the
    // moment Attune leaves the foreground, so the app-switcher snapshot never
    // shows content (Flutter's own cover can miss the snapshot frame).
    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.showSwitcherCover() }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.hideSwitcherCover() }

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

    // Keeps local-only chat files (staged photo picks and uploads, the
    // encrypted cache store) out of device and iCloud backups. See
    // lib/core/services/storage/backup_exclusion.dart; Android excludes the
    // same paths in res/xml/backup_rules.xml + data_extraction_rules.xml.
    let backupChannel = FlutterMethodChannel(
      name: "attune/backup_exclusion",
      binaryMessenger: controller.binaryMessenger
    )
    backupExclusionChannel = backupChannel
    backupChannel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "excludeFromBackup expects a file path",
          details: nil
        ))
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(
          code: "EXCLUDE_FAILED",
          message: "Could not exclude the item from backup",
          details: error.localizedDescription
        ))
      }
    }

    // Spec 1 W6b (§3.3 A2): Apple's Declared Age Range, once, at A2, only
    // in the listed App Store storefronts. Only a status goes back; nothing
    // is stored or sent. DeclaredAgeRange is weak-linked (OTHER_LDFLAGS
    // -weak_framework) and used only on iOS 26 and later.
    let ageChannel = FlutterMethodChannel(
      name: "attune/age_signals",
      binaryMessenger: controller.binaryMessenger
    )
    ageSignalsChannel = ageChannel
    ageChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let storefronts = (call.arguments as? [String: Any])?["storefronts"] as? [String] ?? []
      // Review F1: the Runner target ships at iOS 12.0; Swift concurrency
      // needs iOS 13 (the TogetherLiveActivityChannel pattern).
      if #available(iOS 13.0, *) {
        Task { @MainActor in
          result(await AgeSignalReader.read(
            storefronts: storefronts,
            controller: self?.window?.rootViewController
          ))
        }
      } else {
        result(["status": "unavailable"])
      }
    }

    TogetherLiveActivityChannel.register(with: controller.binaryMessenger)

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

  private func showSwitcherCover() {
    guard switcherCover == nil, let window = window else { return }
    let cover = UIView(frame: window.bounds)
    // Follows light/dark mode, so the switcher shows a plain screen.
    if #available(iOS 13.0, *) {
      cover.backgroundColor = window.backgroundColor ?? .systemBackground
    } else {
      cover.backgroundColor = window.backgroundColor ?? .white
    }
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    switcherCover = cover
  }

  private func hideSwitcherCover() {
    switcherCover?.removeFromSuperview()
    switcherCover = nil
  }
}

/// Spec 1 W6b: Declared Age Range's answer as A2 reads it. 18 and over is
/// adult; a range under 18 is supervised when a guardian declared it,
/// otherwise minor; declined sharing is unknown; below iOS 26, outside the
/// storefronts, or on any error: unavailable (the date of birth decides).
@available(iOS 13.0, *)
enum AgeSignalReader {
  @MainActor
  static func read(storefronts: [String], controller: UIViewController?) async -> [String: String] {
    guard #available(iOS 26.0, *) else { return ["status": "unavailable"] }
    guard let country = await Storefront.current?.countryCode, storefronts.contains(country),
          let controller else {
      return ["status": "unavailable"]
    }
    do {
      let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 18, in: controller)
      switch response {
      case .declinedSharing:
        return ["status": "unknown"]
      case .sharing(let range):
        if let lower = range.lowerBound, lower >= 18 { return ["status": "adult"] }
        if let upper = range.upperBound, upper < 18 {
          return ["status": range.ageRangeDeclaration == .guardianDeclared ? "supervised" : "minor"]
        }
        return ["status": "unknown"]
      @unknown default:
        return ["status": "unknown"]
      }
    } catch {
      return ["status": "unavailable"]
    }
  }
}
