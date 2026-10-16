// ios/TogetherWidgetChecks/main.swift
// Checks CoupleWidgetModel against the Dart vectors (widget spec §8). Not part
// of any Xcode target: run with
//   xcrun swiftc -o "$WS/swiftcheck" ios/TogetherWidget/CoupleWidgetModel.swift ios/TogetherWidgetChecks/main.swift
//   "$WS/swiftcheck" test/features/couple_map/widget/fixtures/couple_widget_vectors.json
import Foundation

let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
let nowMs = (fixture["nowMs"] as! NSNumber).doubleValue
let todayParts = (fixture["today"] as! String).split(separator: "-").map { Int($0)! }
let today = CoupleWidgetModel.epochDay(todayParts[0], todayParts[1], todayParts[2])

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
  if !ok {
    failures += 1
    print("FAIL \(name) \(detail)")
  }
}

check("neutral copy", fixture["neutralHeadline"] as? String == CoupleWidgetModel.neutralHeadline)
let vectors = fixture["vectors"] as! [[String: Any]]
check("vector count", vectors.count >= 20, "\(vectors.count)")
for v in vectors {
  let name = v["name"] as! String
  let e = v["expect"] as! [String: Any]
  let got = CoupleWidgetModel.resolve(v["payload"] as? String, nowMs: nowMs, today: today)
  check(name, got.headline == e["headline"] as? String, "headline \(String(describing: got.headline))")
  check(name, got.headlineIsClock == (e["headlineIsClock"] as! Bool), "headlineIsClock")
  check(name, got.caption == e["caption"] as? String, "caption \(String(describing: got.caption))")
  check(name, got.clockLine == (e["clockLine"] as! Bool), "clockLine")
  check(name, got.clockOffsetMinutes == (e["clockOffsetMinutes"] as? NSNumber)?.intValue, "offset")
  check(name, got.neutral == (e["neutral"] as! Bool), "neutral")
  check(name, got.showMap == (e["showMap"] as! Bool), "showMap")
}

check("epoch 1970", CoupleWidgetModel.epochDay(1970, 1, 1) == 0)
check("epoch 2026-10-16", CoupleWidgetModel.epochDay(2026, 10, 16) == 20742)
check("epoch leap day", CoupleWidgetModel.epochDay(2024, 2, 29) == 19782)

let both = "{\"v\":1,\"validUntilMs\":5000,\"reunionDate\":\"2026-10-28\"}"
check("next: expiry first", CoupleWidgetModel.nextChange(both, nowMs: 1000, nextMidnightMs: 9000) == 5000)
let late = "{\"v\":1,\"validUntilMs\":9000,\"reunionDate\":\"2026-10-28\"}"
check("next: midnight first", CoupleWidgetModel.nextChange(late, nowMs: 1000, nextMidnightMs: 5000) == 5000)
check("next: nothing", CoupleWidgetModel.nextChange("{\"v\":1}", nowMs: 1000, nextMidnightMs: 5000) == nil)
check("next: past expiry", CoupleWidgetModel.nextChange("{\"v\":1,\"validUntilMs\":500}", nowMs: 1000, nextMidnightMs: 5000) == nil)
check("next: malformed", CoupleWidgetModel.nextChange("{", nowMs: 1000, nextMidnightMs: 5000) == nil)

// Timeline plan (final review I1): the next change is always an entry, even
// past the clock's hour, so a late reload never leaves an expired distance.
let base = Date(timeIntervalSince1970: 1_792_152_000) // 2026-10-16 12:00 UTC
let in3h = base.addingTimeInterval(3 * 3_600)
let expiresIn3h = Int(in3h.timeIntervalSince1970 * 1000)
let clockPayload = "{\"v\":1,\"headlineIsClock\":true,\"caption\":\"x\",\"clockOffsetMinutes\":330,\"validUntilMs\":\(expiresIn3h)}"
let clockPlan = CoupleWidgetModel.timelinePlan(
  clockPayload, now: base.addingTimeInterval(10), nextMidnight: base.addingTimeInterval(12 * 3_600), showsClock: true)
check("timeline: expiry entry even past the hour", clockPlan.dates.contains(in3h))
check("timeline: a minute entry for each of the next 60", clockPlan.dates.filter { $0 <= base.addingTimeInterval(3_600) }.count == 60)
check("timeline: reload at the hour", clockPlan.reloadAfter == base.addingTimeInterval(3_600))
let plainPayload = "{\"v\":1,\"headline\":\"x\",\"validUntilMs\":\(expiresIn3h)}"
let plainPlan = CoupleWidgetModel.timelinePlan(
  plainPayload, now: base, nextMidnight: base.addingTimeInterval(12 * 3_600), showsClock: false)
check("timeline: no clock, only the change", plainPlan.dates == [in3h] && plainPlan.reloadAfter == in3h)
let idle = CoupleWidgetModel.timelinePlan("{\"v\":1}", now: base, nextMidnight: base.addingTimeInterval(3_600), showsClock: false)
check("timeline: nothing changes, never reload", idle.dates.isEmpty && idle.reloadAfter == nil)

if failures > 0 {
  print("\(failures) failure(s)")
  exit(1)
}
print("all swift widget checks passed")
