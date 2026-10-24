import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the vendored video_compress (packages/video_compress, see its
/// PATCHES.md): upstream 3.1.4 drops the trim range on iOS/macOS whenever
/// the video keeps its sound, so a trimmed chat video was sent whole.
/// The native export itself can't run under flutter test; the device check
/// lives in docs/reviews/2026-10-24-stories-handoff.md.
void main() {
  test('pubspec.lock resolves video_compress from packages/video_compress', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final entry = RegExp(
      r'^  video_compress:\n((?:    .*\n|      .*\n)+)',
      multiLine: true,
    ).firstMatch(lock);
    expect(
      entry,
      isNotNull,
      reason: 'video_compress missing from pubspec.lock',
    );
    final body = entry!.group(1)!;
    expect(body, contains('source: path'));
    expect(body, contains('path: "packages/video_compress"'));
    expect(File('packages/video_compress/pubspec.yaml').existsSync(), isTrue);
    expect(File('packages/video_compress/LICENSE').existsSync(), isTrue);
    expect(File('packages/video_compress/PATCHES.md').existsSync(), isTrue);
  });

  for (final path in const [
    'packages/video_compress/ios/Classes/SwiftVideoCompressPlugin.swift',
    'packages/video_compress/macos/Classes/VideoCompressPlugin.swift',
  ]) {
    test('$path applies the trim range with or without audio', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is not vendored');
      final src = file.readAsStringSync();
      expect(src, contains('exporter.timeRange ='));
      // Upstream only set the range inside `if !isIncludeAudio { ... }`.
      expect(
        RegExp(
          r'if\s+!isIncludeAudio\s*\{\s*exporter\.timeRange',
        ).hasMatch(src),
        isFalse,
        reason: 'exporter.timeRange is still guarded by !isIncludeAudio',
      );
      final assignments = RegExp(r'exporter\.timeRange\s*=').allMatches(src);
      expect(assignments.length, 1);
      // The assignment must sit at the export setup's own indentation (8
      // spaces), not nested inside any conditional block.
      expect(
        RegExp(
          r'^        exporter\.timeRange\s*=',
          multiLine: true,
        ).hasMatch(src),
        isTrue,
      );
    });
  }
}
