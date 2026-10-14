// Shared by the app (which starts it) and the widget extension (which draws
// it). Together Phase 8c: one plan, its title and times; no names.
import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct TogetherActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
  }
}
