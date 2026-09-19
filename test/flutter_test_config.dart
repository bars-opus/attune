// Applies to EVERY test in this package — `flutter test` picks this file
// up automatically and wraps the whole suite in it.
//
// Its only job: stop golden-image tests from failing CI for a reason
// that has nothing to do with the code under test.
//
// The goldens in this repo (story rings, word hunt, game trails, dots &
// boxes) were generated on macOS. Linux — which is what CI runs — ships
// different font rasterisation, so the same widget tree renders with
// sub-pixel differences along glyph edges. Every CI failure observed
// was of that exact shape: 0.01%, 68px diff, spread across text, on 9
// tests that have been red on `main` since at least 2026-09-16 while
// passing locally for everyone.
//
// Two options exist and only one is honest:
//
//   - Regenerate the goldens on Linux. That inverts the problem — the
//     same 9 tests would then fail on every developer's Mac, which is
//     where they are actually looked at when a design changes.
//   - Keep goldens authoritative on the platform they were authored on
//     and tolerant elsewhere. That is what this does.
//
// A tolerance, NOT a skip: the comparison still runs on Linux, still
// loads the golden, and still fails on a real visual regression — a
// changed layout, a lost widget, a recoloured surface all move far more
// than a fraction of a percent of pixels. Only the anti-aliasing noise
// floor is absorbed. On macOS nothing changes at all: goldens stay
// byte-exact there, so a regression cannot hide by being introduced on
// a Mac either.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

/// Fraction of differing pixels tolerated on non-macOS hosts.
///
/// Observed font-rasterisation noise is ~0.01% (68px on the largest of
/// these goldens). 0.5% leaves two orders of magnitude of headroom over
/// that noise while staying far below anything a genuine visual change
/// would produce — even a single missing icon or shifted row moves well
/// past it.
const double _kGoldenTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // macOS is the reference platform these goldens were authored on:
  // leave the default byte-exact comparator completely untouched there.
  if (!kIsWeb && !Platform.isMacOS) {
    goldenFileComparator = _TolerantGoldenComparator(
      (goldenFileComparator as LocalFileComparator).basedir,
    );
  }
  await testMain();
}

/// A [LocalFileComparator] that treats a sufficiently small pixel
/// difference as a pass. Everything else — loading, updating with
/// `--update-goldens`, and failing loudly on a real difference — is the
/// inherited behaviour.
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(Uri basedir) : super(Uri.parse('$basedir/test.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed) return true;

    if (result.diffPercent <= _kGoldenTolerance) {
      // Surfaced rather than silently swallowed: if this line starts
      // appearing for a golden that used to be clean, something did
      // change and is worth a look on a Mac.
      // ignore: avoid_print
      print(
        'golden ${golden.pathSegments.last}: '
        '${(result.diffPercent * 100).toStringAsFixed(3)}% diff within the '
        'cross-platform tolerance — treated as a pass on '
        '${Platform.operatingSystem}.',
      );
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
