// ios/TogetherWidget/CoupleWidgetModel.swift
// The distance widget's view model (widget spec §3.1, §6.2). Mirrors Dart's
// resolveCoupleWidget; the live clock is SwiftUI's own, so only its offset and
// slot are returned. Foundation only: checked with swiftc against the vectors.
import Foundation

struct CoupleWidgetView: Equatable {
  let headline: String?
  let headlineIsClock: Bool
  let caption: String?
  let clockLine: Bool
  let clockOffsetMinutes: Int?
  let neutral: Bool
  let showMap: Bool
}

enum CoupleWidgetModel {
  static let neutralHeadline = "Nothing to show yet"
  static let neutral = CoupleWidgetView(
    headline: neutralHeadline, headlineIsClock: false, caption: nil,
    clockLine: false, clockOffsetMinutes: nil, neutral: true, showMap: false)

  private struct Payload: Decodable {
    let v: Int
    let headline: String?
    let headlineIsClock: Bool?
    let caption: String?
    let clockOffsetMinutes: Int?
    let clockLine: Bool?
    let validUntilMs: Double?
    let reunionDate: String?
  }

  private static func parse(_ raw: String?) -> Payload? {
    guard let data = raw?.data(using: .utf8),
          let payload = try? JSONDecoder().decode(Payload.self, from: data),
          payload.v == 1
    else { return nil }
    return payload
  }

  /// Days since 1970-01-01 for a civil date (Hinnant), calendar-free.
  static func epochDay(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
  }

  private static func epochDay(_ date: String) -> Int? {
    let parts = date.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
    else { return nil }
    return epochDay(y, m, d)
  }

  private static func countdown(_ days: Int) -> String {
    switch days {
    case 0: return "Together today"
    case 1: return "Together tomorrow"
    default: return "\(days) days until you're together"
    }
  }

  static func resolve(_ raw: String?, nowMs: Double, today: Int) -> CoupleWidgetView {
    guard let p = parse(raw) else { return neutral }
    let live = p.validUntilMs.map { $0 > nowMs } ?? false
    var days: Int?
    if let date = p.reunionDate, let day = epochDay(date), day - today >= 0 {
      days = day - today
    }
    let off = p.clockOffsetMinutes
    let clockLine = (p.clockLine ?? false) && off != nil
    if live {
      if let days = days {
        return CoupleWidgetView(
          headline: countdown(days), headlineIsClock: false, caption: p.caption,
          clockLine: clockLine, clockOffsetMinutes: clockLine ? off : nil,
          neutral: false, showMap: true)
      }
      if p.headlineIsClock == true, let off = off {
        return CoupleWidgetView(
          headline: nil, headlineIsClock: true, caption: p.caption,
          clockLine: false, clockOffsetMinutes: off, neutral: false, showMap: true)
      }
      if let headline = p.headline {
        return CoupleWidgetView(
          headline: headline, headlineIsClock: false, caption: p.caption,
          clockLine: clockLine, clockOffsetMinutes: clockLine ? off : nil,
          neutral: false, showMap: true)
      }
    }
    if let days = days {
      return days <= 1
        ? CoupleWidgetView(
          headline: countdown(days), headlineIsClock: false, caption: nil,
          clockLine: false, clockOffsetMinutes: nil, neutral: false, showMap: false)
        : CoupleWidgetView(
          headline: "\(days) days", headlineIsClock: false,
          caption: "until you're together", clockLine: false,
          clockOffsetMinutes: nil, neutral: false, showMap: false)
    }
    return neutral
  }

  /// When the view next changes by itself: the distance expiring, or local
  /// midnight while a reunion counts down (spec §4.2).
  static func nextChange(_ raw: String?, nowMs: Double, nextMidnightMs: Double) -> Double? {
    guard let p = parse(raw) else { return nil }
    var candidates: [Double] = []
    if let until = p.validUntilMs, until > nowMs { candidates.append(until) }
    if p.reunionDate != nil { candidates.append(nextMidnightMs) }
    return candidates.min()
  }

  /// The entry dates after `now`, and when to ask WidgetKit again (spec §4.2).
  /// While a clock shows, one entry per minute for the next hour (WidgetKit has
  /// no live wall-clock text), then reload. The next change is always an entry,
  /// even past that hour: if WidgetKit defers the reload, the distance still
  /// leaves on time (final review I1).
  static func timelinePlan(
    _ raw: String?, now: Date, nextMidnight: Date, showsClock: Bool
  ) -> (dates: [Date], reloadAfter: Date?) {
    let next = nextChange(
      raw, nowMs: now.timeIntervalSince1970 * 1000,
      nextMidnightMs: nextMidnight.timeIntervalSince1970 * 1000
    ).map { Date(timeIntervalSince1970: $0 / 1000) }
    var dates: [Date] = []
    var reloadAfter = next
    if showsClock {
      let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
      let horizon = minute.addingTimeInterval(3_600)
      for i in 1...60 { dates.append(minute.addingTimeInterval(Double(i) * 60)) }
      reloadAfter = horizon
    }
    if let next = next { dates.append(next) }
    return (Array(Set(dates.filter { $0 > now })).sorted(), reloadAfter)
  }
}
