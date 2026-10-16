// ios/TogetherWidget/CoupleWidget.swift
// The distance widget (widget spec §3, §6.2). Shows only what the app wrote to
// the App Group; never touches the network; no names, places or app words.
import SwiftUI
import UIKit
import WidgetKit

private let coupleAppGroup = "group.com.barsopus.attune"
private let couplePayloadKey = "couple_widget_v1"
private let coupleMapKey = "couple_widget_map"
private let coupleLink = URL(string: "attune://planning?tab=map")!

struct CoupleEntry: TimelineEntry {
  let date: Date
  let view: CoupleWidgetView
  let map: UIImage?
}

private func dayNumber(_ date: Date) -> Int {
  let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
  return CoupleWidgetModel.epochDay(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
}

private func loadRaw() -> String? {
  UserDefaults(suiteName: coupleAppGroup)?.string(forKey: couplePayloadKey)
}

/// The image by file name inside our own container; a stored absolute path
/// is never trusted (it changes with a reinstall; spec §4.4).
private func loadMap() -> UIImage? {
  guard let stored = UserDefaults(suiteName: coupleAppGroup)?.string(forKey: coupleMapKey),
        let container = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: coupleAppGroup)
  else { return nil }
  let name = (stored as NSString).lastPathComponent
  let url = container.appendingPathComponent("home_widget").appendingPathComponent(name)
  return UIImage(contentsOfFile: url.path)
}

private func makeEntry(at date: Date, raw: String?, map: UIImage?) -> CoupleEntry {
  let view = CoupleWidgetModel.resolve(
    raw, nowMs: date.timeIntervalSince1970 * 1000, today: dayNumber(date))
  return CoupleEntry(date: date, view: view, map: view.showMap ? map : nil)
}

/// The gallery and placeholders show sample lines, never the real ones: the
/// gallery is often seen over someone's shoulder (spec §3.2).
private let sampleEntry = CoupleEntry(
  date: Date(),
  view: CoupleWidgetView(
    headline: "Together tomorrow", headlineIsClock: false, caption: "5.1k km apart",
    clockLine: false, clockOffsetMinutes: nil, neutral: false, showMap: false),
  map: nil)

struct CoupleProvider: TimelineProvider {
  func placeholder(in context: Context) -> CoupleEntry { sampleEntry }

  func getSnapshot(in context: Context, completion: @escaping (CoupleEntry) -> Void) {
    if context.isPreview {
      completion(sampleEntry)
      return
    }
    completion(makeEntry(at: Date(), raw: loadRaw(), map: loadMap()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CoupleEntry>) -> Void) {
    let now = Date()
    let raw = loadRaw()
    let map = loadMap()
    // Calendar arithmetic, not +24 h: the fall-back day is 25 hours long.
    let midnight = Calendar.current.date(
      byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
      ?? now.addingTimeInterval(86_400)
    let first = makeEntry(at: now, raw: raw, map: map)
    let plan = CoupleWidgetModel.timelinePlan(
      raw, now: now, nextMidnight: midnight,
      showsClock: first.view.headlineIsClock || first.view.clockLine)
    let policy: TimelineReloadPolicy = plan.reloadAfter.map { .after($0) } ?? .never
    completion(Timeline(
      entries: [first] + plan.dates.map { makeEntry(at: $0, raw: raw, map: map) },
      policy: policy))
  }
}

/// The partner's wall time as fixed text: the entry's instant moved by the
/// gap between their offset and this phone's, so the phone's own formatter
/// (12/24 h, locale) prints their time. No reliance on the environment's
/// time zone (spec §3.1; Review Focus 4).
private struct ClockText: View {
  let date: Date
  let offsetMinutes: Int

  var body: some View {
    let shift = TimeInterval(offsetMinutes * 60 - TimeZone.current.secondsFromGMT(for: date))
    return Text(date.addingTimeInterval(shift), style: .time) + Text(" there")
  }
}

private struct CoupleLines: View {
  let entry: CoupleEntry

  var body: some View {
    let v = entry.view
    VStack(alignment: .leading, spacing: 4) {
      if v.neutral {
        HStack(spacing: 6) {
          Image(systemName: "heart").foregroundColor(.secondary)
          Text(CoupleWidgetModel.neutralHeadline)
            .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
        }
      } else {
        if v.headlineIsClock, let off = v.clockOffsetMinutes {
          ClockText(date: entry.date, offsetMinutes: off)
            .font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        } else if let headline = v.headline {
          Text(headline)
            .font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.6)
        }
        if let caption = v.caption {
          Text(caption).font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
        if v.clockLine, let off = v.clockOffsetMinutes {
          ClockText(date: entry.date, offsetMinutes: off)
            .font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // One spoken sentence, the live time included (spec §6.2).
    .accessibilityElement(children: .combine)
    .modifier(CouplePrivacy())
  }
}

private struct MapSlot: View {
  let image: UIImage

  var body: some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFill()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// Tinted and clear home screens (iOS 18) would flatten the image to a slab:
/// there, the text layout only (spec §3.2).
private struct FullColorOnly<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(iOSApplicationExtension 16.0, *) {
      FullColorGate(content: content)
    } else {
      content()
    }
  }
}

@available(iOSApplicationExtension 16.0, *)
private struct FullColorGate<Content: View>: View {
  @Environment(\.widgetRenderingMode) private var mode
  let content: () -> Content

  var body: some View {
    if mode == .fullColor { content() }
  }
}

struct CoupleWidgetContent: View {
  @Environment(\.widgetFamily) private var family
  let entry: CoupleEntry

  var body: some View {
    Group {
      if family == .systemMedium, let map = entry.map {
        HStack(spacing: 12) {
          FullColorOnly { MapSlot(image: map).frame(width: 130) }
          CoupleLines(entry: entry)
        }
      } else {
        CoupleLines(entry: entry)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetURL(coupleLink)
    .modifier(CoupleBackground())
  }
}

/// Best effort only: iOS redacts this on a locked phone just when the user
/// turned off widget access while locked (spec §4.5).
private struct CouplePrivacy: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 15.0, *) {
      content.privacySensitive()
    } else {
      content
    }
  }
}

private struct CoupleBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content.padding()
    }
  }
}

struct CoupleWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CoupleWidget", provider: CoupleProvider()) { entry in
      CoupleWidgetContent(entry: entry)
    }
    .configurationDisplayName("Apart")
    .description("Time and distance between you two. Turn it on in Attune first.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
