// Together lock-screen plan (Phase 8c R2): the title as written, the times,
// a countdown until it starts. No names, no app wording.
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
private struct Countdown: View {
  let state: TogetherActivityAttributes.ContentState

  var body: some View {
    // Counts down to the start and stops at zero; the activity goes stale at
    // the start (the app sets staleDate), when the times take over.
    Text(timerInterval: state.start.addingTimeInterval(-4 * 3600)...state.start, countsDown: true)
      .monospacedDigit()
  }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
  let state: TogetherActivityAttributes.ContentState
  let started: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        // Once it has started the title goes: a card left up after the plan
        // (until the app is next opened) shows only its times.
        if !started {
          Text(state.title).font(.headline).lineLimit(1)
        }
        Text(state.start...state.end)
          .font(started ? .headline : .subheadline)
          .foregroundStyle(started ? .primary : .secondary)
      }
      Spacer(minLength: 8)
      if !started {
        Countdown(state: state)
          .font(.title3)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 96)
      }
    }
    .padding(16)
    .privacySensitive()
  }
}

@available(iOS 16.2, *)
struct TogetherLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TogetherActivityAttributes.self) { context in
      LockScreenView(state: context.state, started: context.isStale)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if !context.isStale {
            Text(context.state.title).font(.headline).lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.start, style: .time)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if context.isStale {
            Text(context.state.start...context.state.end).foregroundStyle(.secondary)
          } else {
            Countdown(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "calendar")
      } compactTrailing: {
        if context.isStale {
          Text(context.state.start, style: .time).frame(maxWidth: 56)
        } else {
          Countdown(state: context.state).frame(maxWidth: 56)
        }
      } minimal: {
        Image(systemName: "calendar")
      }
    }
  }
}
