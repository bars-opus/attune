// Spec 2 W4a (§3.3.2 "During capture", §3.3.5; R-10, R-11): the capture
// seam. The vendor's capture view runs the video and the ID document; the
// app adds its own prompts, spoken through the screen reader when one is
// on, with a haptic tick unless reduce motion is on. W4a's launcher runs
// the development capture for the fake vendor only (a practice screen that
// plays the prompts and lets a tester pick the fake's scenario); any other
// vendor answers `unavailable` until its native capture view lands with
// the vendor contract (R-10, owner checklist). Nothing here records,
// stores or uploads an image.
import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DatingCaptureKind { done, cancelled, unavailable }

class DatingCaptureResult {
  const DatingCaptureResult(this.kind, {this.scenario});

  static const cancelled = DatingCaptureResult(DatingCaptureKind.cancelled);
  static const unavailable = DatingCaptureResult(DatingCaptureKind.unavailable);

  final DatingCaptureKind kind;

  /// The fake's scenario a tester picked (development only).
  final String? scenario;
}

abstract class DatingCaptureLauncher {
  /// The video check for the vendor session [vendorRef].
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  });

  /// The ID document capture for the vendor job [vendorRef].
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  });
}

/// The fake vendor's scenarios the practice screen offers (§3.3.5; the
/// server refuses a scenario outside fake mode).
const datingFakeVideoScenarios = [
  'pass',
  'liveness_fail',
  'under_25',
  'uncertain',
  'far_below',
  'photo_mismatch',
  'vendor_down',
];
const datingFakeIdScenarios = [
  'id_pass',
  'id_fail',
  'id_dob_mismatch',
  'id_minor',
  'id_pending',
];

class DatingDevCaptureLauncher implements DatingCaptureLauncher {
  const DatingDevCaptureLauncher();

  Future<DatingCaptureResult> _practice(
    BuildContext context,
    String vendor,
    List<String> scenarios,
    bool video,
  ) async {
    // Fix round 1 (M-5): never in a release build either (both servers
    // already refuse the fake outside development).
    if (vendor != 'fake' || kReleaseMode) {
      return DatingCaptureResult.unavailable;
    }
    // Spec 2 W8a round 2 (Re-1-M2): nothing opens once Dating is blank.
    if (datingSheetRefused) return DatingCaptureResult.cancelled;
    final result = await Navigator.of(context).push<DatingCaptureResult>(
      MaterialPageRoute(
        settings: datingSheetSettings('capture'),
        fullscreenDialog: true,
        builder:
            (_) => DatingSheetTracker(
              child: DatingPracticeCaptureScreen(
                scenarios: scenarios,
                video: video,
              ),
            ),
      ),
    );
    return result ?? DatingCaptureResult.cancelled;
  }

  @override
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) => _practice(context, vendor, datingFakeVideoScenarios, true);

  @override
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) => _practice(context, vendor, datingFakeIdScenarios, false);
}

final datingCaptureLauncherProvider = Provider<DatingCaptureLauncher>(
  (ref) => const DatingDevCaptureLauncher(),
);

/// Attune's own capture prompts (§3.3.2, §3.15 D11): spoken by the screen
/// reader when one is on (R-10: never twice, so the visible line is not a
/// live region), and a selection tick unless reduce motion is on.
class DatingCaptureVoice {
  const DatingCaptureVoice(this.haptics);

  final Haptics haptics;

  void prompt(BuildContext context, String text) {
    final media = MediaQuery.maybeOf(context);
    if (media?.accessibleNavigation ?? false) {
      SemanticsService.announce(text, Directionality.of(context));
    }
    if (!(media?.disableAnimations ?? false)) haptics.selection();
  }
}

final datingCaptureVoiceProvider = Provider<DatingCaptureVoice>(
  (ref) => DatingCaptureVoice(ref.watch(hapticsProvider)),
);

/// The time between two prompts on the practice screen.
const kDatingPromptGap = Duration(milliseconds: 1200);

/// The development capture (fake vendor only): the three prompts in turn,
/// the scenario the fake will play, Done or Cancel. No camera.
class DatingPracticeCaptureScreen extends ConsumerStatefulWidget {
  const DatingPracticeCaptureScreen({
    super.key,
    required this.scenarios,
    required this.video,
  });

  final List<String> scenarios;
  final bool video;

  @override
  ConsumerState<DatingPracticeCaptureScreen> createState() =>
      _DatingPracticeCaptureScreenState();
}

class _DatingPracticeCaptureScreenState
    extends ConsumerState<DatingPracticeCaptureScreen> {
  int _prompt = -1;
  late String _scenario = widget.scenarios.first;
  Timer? _timer;

  List<String> _prompts(AppLocalizations loc) => [
    loc.dating_capturePromptCloser,
    loc.dating_capturePromptHold,
    loc.dating_capturePromptDone,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  void _next() {
    if (!mounted) return;
    final prompts = _prompts(AppLocalizations.of(context)!);
    if (_prompt + 1 >= prompts.length) return;
    setState(() => _prompt++);
    ref.read(datingCaptureVoiceProvider).prompt(context, prompts[_prompt]);
    if (_prompt + 1 < prompts.length) {
      _timer = Timer(kDatingPromptGap, _next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final prompts = _prompts(loc);
    return FlowFrame(
      title: loc.dating_capturePracticeTitle,
      onBack: () => Navigator.of(context).pop(DatingCaptureResult.cancelled),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _prompt < 0 ? '' : prompts[_prompt],
            key: const ValueKey('dating_capture_prompt'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            loc.dating_capturePracticeBody,
            style: theme.textTheme.bodyMedium,
          ),
          for (final s in widget.scenarios)
            RadioListTile<String>(
              value: s,
              groupValue: _scenario,
              contentPadding: EdgeInsets.zero,
              title: Text(s),
              onChanged: (v) => setState(() => _scenario = v ?? _scenario),
            ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_continue,
          onPressed:
              () => Navigator.of(context).pop(
                DatingCaptureResult(
                  DatingCaptureKind.done,
                  scenario: _scenario,
                ),
              ),
        ),
        FlowTextLink(
          label: loc.dating_captureCancel,
          alignment: AlignmentDirectional.centerStart,
          onPressed:
              () => Navigator.of(context).pop(DatingCaptureResult.cancelled),
        ),
      ],
    );
  }
}
