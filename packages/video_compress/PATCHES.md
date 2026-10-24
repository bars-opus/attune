# Vendored video_compress

Upstream: [video_compress](https://pub.dev/packages/video_compress) **3.1.4**
(MIT, see LICENSE), copied unchanged except for the patches below. The app
points at this copy through `dependency_overrides` in the root pubspec.yaml.
Dart APIs are unchanged.

## Patches (2026-10-24)

`ios/Classes/SwiftVideoCompressPlugin.swift` and
`macos/Classes/VideoCompressPlugin.swift`, `compressVideo`:

1. **Trim range ignored with audio.** Upstream set `exporter.timeRange` only
   inside `if !isIncludeAudio`, and with audio `getComposition` exports the
   whole source asset, so `startTime`/`duration` were dropped and a trimmed
   video with sound was exported whole. The range is now always set: the
   source time range on the full asset (audio kept), and a zero-based range
   of the same length on the video-only composition (which was built from
   the range at time zero, so upstream's source-time range cut its start
   when `startTime > 0`). `getComposition` is unchanged.
2. **Duration clamp.** When `startTime + duration` reached past the end,
   upstream used the full video length as the duration (a range running past
   the end). It now uses what is left after the start.

Android is untouched (its trim semantics are handled in
`lib/features/chat/domain/services/chat_video_preparer.dart`).

Guard: `test/core/vendored_video_compress_test.dart`.
When upgrading, re-check upstream for these bugs before dropping the patch.
