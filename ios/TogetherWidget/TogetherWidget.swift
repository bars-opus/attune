// Together "Next" card (Phase 8a). Reads only what the app wrote to the
// App Group; shows nothing that has already ended; adds no names or app words.
import SwiftUI
import WidgetKit

private let appGroup = "group.com.barsopus.attune"
private let payloadKey = "together_widget_v1"

struct Line: Decodable {
  let title: String
  let label: String
  let start: Double
  let end: Double
}

private struct Payload: Decodable {
  let v: Int
  let lines: [Line]
}

struct NextEntry: TimelineEntry {
  let date: Date
  let lines: [Line]
}

private func loadLines() -> [Line] {
  guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: payloadKey),
        let data = raw.data(using: .utf8),
        let payload = try? JSONDecoder().decode(Payload.self, from: data)
  else { return [] }
  return payload.lines
}

private func current(_ lines: [Line], at date: Date) -> [Line] {
  let ms = date.timeIntervalSince1970 * 1000
  return Array(lines.filter { $0.end > ms }.prefix(2))
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> NextEntry {
    NextEntry(date: Date(), lines: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
    let now = Date()
    completion(NextEntry(date: now, lines: current(loadLines(), at: now)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
    let now = Date()
    let all = loadLines()
    // A new entry whenever a line ends, so a passed plan drops off by itself.
    let ends = all.map { Date(timeIntervalSince1970: $0.end / 1000) }.filter { $0 > now }.sorted()
    let entries = ([now] + ends.prefix(5)).map { NextEntry(date: $0, lines: current(all, at: $0)) }
    let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
    completion(Timeline(entries: entries, policy: .after(refresh)))
  }
}

struct TogetherWidgetView: View {
  var entry: NextEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Next").font(.caption).foregroundColor(.secondary)
      if entry.lines.isEmpty {
        Text("Nothing to show").font(.subheadline).foregroundColor(.secondary)
      } else {
        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
          VStack(alignment: .leading, spacing: 1) {
            Text(line.title).font(.subheadline).bold().lineLimit(1)
            Text(line.label).font(.caption).foregroundColor(.secondary).lineLimit(1)
          }
          .modifier(Redacted())
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .modifier(WidgetBackground())
  }
}

// On a locked phone (StandBy, lock-screen widgets) the system blanks plan
// titles and times: discreet by default (Phase 8a owner decision).
private struct Redacted: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 15.0, *) {
      content.privacySensitive()
    } else {
      content
    }
  }
}

private struct WidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content.padding()
    }
  }
}

struct TogetherWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TogetherWidget", provider: Provider()) { entry in
      TogetherWidgetView(entry: entry)
    }
    .configurationDisplayName("Next")
    .description("Your next plans. Turn it on in the app first.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// The card (8a) and, where iOS supports it, the lock-screen plan (8c).
@main
struct TogetherWidgets: WidgetBundle {
  var body: some Widget {
    TogetherWidget()
    if #available(iOS 16.2, *) {
      TogetherLiveActivity()
    }
  }
}
