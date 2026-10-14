// Together Phase 8c: starts, updates and ends the lock-screen plan. Only the
// app writes it, while it's open; iOS ends it within 8 hours regardless (R3).
import ActivityKit
import Flutter
import Foundation
import UIKit

enum TogetherLiveActivityChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    // Whenever the app comes forward (from anywhere, not just Together), a
    // plan that's over is taken off the lock screen.
    if #available(iOS 16.2, *) {
      NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in await endFinished() }
      }
    }
    let channel = FlutterMethodChannel(name: "attune/together_live", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(call.method == "supported" ? false : nil)
        return
      }
      switch call.method {
      case "supported":
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      case "show":
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let start = args["start"] as? NSNumber,
              let end = args["end"] as? NSNumber
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "show expects title, start, end", details: nil))
          return
        }
        let state = TogetherActivityAttributes.ContentState(
          title: title,
          start: Date(timeIntervalSince1970: start.doubleValue / 1000),
          end: Date(timeIntervalSince1970: end.doubleValue / 1000)
        )
        Task { @MainActor in
          await show(state)
          result(nil)
        }
      case "end":
        Task { @MainActor in
          await endAll()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// One activity at most: update the running one, or start one.
  @available(iOS 16.2, *)
  private static func show(_ state: TogetherActivityAttributes.ContentState) async {
    // Stale from the start: the countdown gives way to the plan's times.
    let content = ActivityContent(state: state, staleDate: state.start)
    let all = Activity<TogetherActivityAttributes>.activities
    let running = all.filter { $0.activityState == .active || $0.activityState == .stale }
    if let current = running.first {
      await current.update(content)
      for extra in all where extra.id != current.id {
        await extra.end(nil, dismissalPolicy: .immediate)
      }
    } else {
      // One iOS already ended (still shown greyed) goes before a new one.
      for old in all {
        await old.end(nil, dismissalPolicy: .immediate)
      }
      _ = try? Activity.request(attributes: TogetherActivityAttributes(), content: content, pushType: nil)
    }
  }

  @available(iOS 16.2, *)
  private static func endFinished() async {
    let now = Date()
    for activity in Activity<TogetherActivityAttributes>.activities
    where activity.content.state.end <= now {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<TogetherActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
