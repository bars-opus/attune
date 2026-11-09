// Spec 2 (§3.2, §3.14): the setup steps, in order, and the screen for each.
// Each batch adds its steps' cases to datingStepScreen; a step not built yet
// opens Me (R-10).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/setup/children_step.dart';
import 'package:attune/features/dating/setup/faith_step.dart';
import 'package:attune/features/dating/setup/how_step.dart';
import 'package:attune/features/dating/setup/looking_for_step.dart';
import 'package:attune/features/dating/setup/meet_step.dart';
import 'package:attune/features/dating/setup/photos_step.dart';
import 'package:attune/features/dating/setup/preview_step.dart';
import 'package:attune/features/dating/setup/prompts_step.dart';
import 'package:attune/features/dating/setup/ready_step.dart';
import 'package:attune/features/dating/setup/verify_step.dart';
import 'package:attune/features/dating/setup/privacy_step.dart';
import 'package:attune/features/dating/setup/where_step.dart';
import 'package:attune/features/dating/setup/you_step.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.14's step ids after D0, in order. "Step {n} of 12" counts from
/// looking-for (1) to ready (12).
const datingSetupOrder = [
  'how',
  'looking-for',
  'where',
  'privacy',
  'you',
  'meet',
  'children',
  'faith',
  'photos',
  'prompts',
  'verify',
  'preview',
  'ready',
];

int? datingStepNumber(String step) {
  final i = datingSetupOrder.indexOf(step);
  return i >= 1 ? i : null;
}

/// How a step moves on: [next] opens a step ('done' is Me), [back] the step
/// before (or Me), [toMe] leaves setup.
class DatingStepNav {
  const DatingStepNav({
    required this.next,
    required this.back,
    required this.toMe,
    this.from,
    this.askAgain,
  });

  final void Function(String step) next;
  final VoidCallback back;
  final VoidCallback toMe;

  /// R-40: the place a `?from=` step goes back to ('preview', 'settings',
  /// 'ready', 'section'), or null when it walks forward.
  final String? from;

  /// Final fix (I-3): with [from], a save cleared a later answer the
  /// server needs again; opens that step in this one's place, with the
  /// same [from] (so the step after it goes back).
  final void Function(String step)? askAgain;
}

Widget? datingStepScreen(String step, DatingStepNav nav) => switch (step) {
  'wait' => DatingWaitStep(nav: nav),
  'how' => DatingHowStep(nav: nav),
  'looking-for' => DatingLookingForStep(nav: nav),
  'where' => DatingWhereStep(nav: nav),
  'privacy' => DatingPrivacyStep(nav: nav),
  'you' => DatingYouStep(nav: nav),
  'meet' => DatingMeetStep(nav: nav),
  'children' => DatingChildrenStep(nav: nav),
  'faith' => DatingFaithStep(nav: nav),
  'photos' => DatingPhotosStep(nav: nav),
  'prompts' => DatingPromptsStep(nav: nav),
  'verify' => DatingVerifyStep(nav: nav),
  'preview' => DatingPreviewStep(nav: nav),
  'ready' => DatingReadyStep(nav: nav),
  _ => null,
};

/// R-40: the places a step opened with `?from=` goes back to. Tokens
/// only, never a path (so a link can't send anyone outside Dating) and
/// never anything typed. Final fix (M-8): 'section' is Me's Dating
/// section (the kill-switch "Choose again").
const _datingReturnPlaces = {'preview', 'settings', 'ready', 'section'};

/// Final fix (M-9): where a `from` step goes when there is no page to go
/// back to (it was opened again through the unlock).
String _datingReturnLocation(String from) => switch (from) {
  'settings' => DatingPaths.settings,
  'section' => homeLocation(tab: AppTab.me),
  _ => DatingPaths.step(from),
};

String? datingStepFrom(String? raw) =>
    _datingReturnPlaces.contains(raw) ? raw : null;

/// Where [next] ('prompts', or 'prompts?from=preview') opens: always a
/// /dating/setup/ path, with no query but a known `from`. Null for a step
/// id that isn't one.
String? datingStepLocation(String next) {
  final at = next.indexOf('?');
  final step = at < 0 ? next : next.substring(0, at);
  if (!RegExp(r'^[a-z][a-z-]*$').hasMatch(step)) return null;
  final from =
      at < 0
          ? null
          : datingStepFrom(
            Uri.splitQueryString(next.substring(at + 1))['from'],
          );
  return Uri(
    path: DatingPaths.step(step),
    queryParameters: from == null ? null : {'from': from},
  ).toString();
}

/// The step pages that have already moved on (T6 fix 1, M-2): a second
/// tap before the next page is up, or during its transition, pushes
/// nothing more. Cleared when the person comes back to the page.
final _movedOn = Expando<bool>('datingStepMovedOn');

class DatingSetupStepRoute extends StatelessWidget {
  const DatingSetupStepRoute({super.key, required this.step, this.from});

  final String step;

  /// 'preview', 'settings' (R-40), 'ready' (D13's Verify it's you,
  /// T11 fix 1 M-5) or 'section' (final fix M-8): moving on goes back there.
  final String? from;

  @override
  Widget build(BuildContext context) {
    void toMe() => context.go(homeLocation(tab: AppTab.me));
    final place = datingStepFrom(from);
    final nav = DatingStepNav(
      from: place,
      next: (next) {
        if (next == 'done') return toMe();
        if (_movedOn[context] == true) return;
        final location = datingStepLocation(next);
        if (location == null) return toMe();
        _movedOn[context] = true;
        if (place != null && !next.contains('?')) {
          // M-8: Me's section shows the home as it is now (for Resume).
          if (place == 'section') _refreshHome(context);
          if (context.canPop()) return context.pop();
          // M-9: no page to go back to: the place itself, never forward.
          return context.go(_datingReturnLocation(place));
        }
        context.push(location).whenComplete(() {
          _movedOn[context] = null;
        });
      },
      askAgain:
          place == null
              ? null
              : (step) {
                if (_movedOn[context] == true) return;
                final location = datingStepLocation('$step?from=$place');
                if (location == null) return toMe();
                _movedOn[context] = true;
                context.pushReplacement(location);
              },
      back: () => context.canPop() ? context.pop() : toMe(),
      toMe: toMe,
    );
    return datingStepScreen(step, nav) ?? _NotBuiltYet(onShown: toMe);
  }
}

void _refreshHome(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.invalidate(
    datingHomeProvider(container.read(datingAccountProvider)),
  );
}

class _NotBuiltYet extends StatefulWidget {
  const _NotBuiltYet({required this.onShown});

  final VoidCallback onShown;

  @override
  State<_NotBuiltYet> createState() => _NotBuiltYetState();
}

class _NotBuiltYetState extends State<_NotBuiltYet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

/// D0 (W2's screen) at /dating/setup/wait: "Set up Dating now" opens the
/// step the server says is next.
class DatingWaitStep extends ConsumerWidget {
  const DatingWaitStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GentleWaitScreen(
    onBack: nav.back,
    onSetUp: () async {
      final gateway = ref.read(datingHomeGatewayProvider);
      var next = 'how';
      try {
        next = (await gateway.read()).nextStep ?? 'how';
      } catch (_) {
        // Unreadable: setup starts at the beginning; each step resumes.
      }
      if (context.mounted) nav.next(next);
    },
  );
}
