import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/path_step.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings -> "How you use Attune" (Spec 1 §3.12), under flow_paths_v2.
SettingsConfig? howYouUseSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(flowPathsV2Provider)) return null;
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'how_you_use_attune',
    title: loc.flow_howTitle,
    subtitle: loc.flow_howSubtitle,
    icon: Icons.alt_route_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.howYouUseAttune,
    onTap: () => context.push(RouteNames.howYouUseAttune),
    iconColor: Colors.teal,
    order: 4,
  );
}

/// Settings -> How you use Attune (Spec 1 §3.12): the three paths with A6's
/// lines; every switch is silent to everyone else. An open or paused
/// shared space has to be paused or ended first (the Spec 3a actions).
class HowYouUseAttuneScreen extends ConsumerStatefulWidget {
  const HowYouUseAttuneScreen({super.key});

  @override
  ConsumerState<HowYouUseAttuneScreen> createState() =>
      _HowYouUseAttuneScreenState();
}

class _HowYouUseAttuneScreenState extends ConsumerState<HowYouUseAttuneScreen> {
  bool _busy = false;

  /// The live read failed and no path is known: say so, offer a retry
  /// (never a spinner forever offline).
  bool _unreachable = false;

  String? get _userId => ref.read(homeAuthProvider).currentUser?.id;

  @override
  void initState() {
    super.initState();
    _read();
  }

  /// Back, or Settings when the screen was opened on its own (a deep link
  /// with nothing under it; B7 review N-3).
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.settings);
    }
  }

  /// The path is read live (D20): ask the server now. Never a spinner
  /// forever (B7 review M-5): signed out leaves; an answer with no path yet
  /// goes home, where the gate asks for it; no answer says so.
  Future<void> _read() async {
    final userId = _userId;
    if (userId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _leave();
      });
      return;
    }
    if (_unreachable) setState(() => _unreachable = false);
    final answer = await ref.read(homeStateProvider(userId).notifier).refresh();
    if (!mounted) return;
    if (ref.read(homeStateProvider(userId)).path != null) return;
    if (answer != null) {
      context.go(homeLocation());
    } else {
      setState(() => _unreachable = true);
    }
  }

  Future<void> _choose(HomeSnapshot home, AppPath to) async {
    if (_busy || home.path == to) return;
    final open = home.link == LinkState.linked || home.link == LinkState.paused;
    if (home.path == AppPath.relationship && open) {
      await showSharedSpaceSheet(context, home);
      return;
    }
    setState(() => _busy = true);
    final outcome = await switchPath(context, ref, to: to, home: home);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == PathChoiceOutcome.relationshipOpen) {
      // B4 review M-2: the space opened since the screen read it.
      await showSharedSpaceSheetAfterRefusal(context, home);
      return;
    }
    if (outcome == PathChoiceOutcome.done && to != AppPath.relationship) {
      context.go(homeLocation(tab: AppTab.forPath(to)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final userId = _userId;
    final home =
        userId == null
            ? HomeSnapshot.unknown
            : ref.watch(homeStateProvider(userId));
    final current = home.path;
    final options = [
      (
        AppPath.relationship,
        loc.flow_pathRelationshipTitle,
        loc.flow_pathRelationshipLine,
      ),
      (AppPath.dating, loc.flow_pathDatingTitle, loc.flow_pathDatingLine),
      (AppPath.justMe, loc.flow_pathJustMeTitle, loc.flow_pathJustMeLineFull),
    ];
    return FlowFrame(
      title: loc.flow_howTitle,
      onBack: _leave,
      body:
          current == null
              ? _unreachable
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FlowErrorLine(
                        text: loc.flow_switchOffline,
                        liveRegion: true,
                      ),
                      const SizedBox(height: Spacing.sm),
                      FlowTextLink(
                        label: loc.flow_tryAgain,
                        alignment: AlignmentDirectional.centerStart,
                        onPressed: _read,
                      ),
                    ],
                  )
                  : const Center(child: CircularProgressIndicator())
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    container: true,
                    label: loc.flow_pathGroupSemantics,
                    explicitChildNodes: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (path, title, line) in options) ...[
                          PathChoiceCard(
                            title: title,
                            line: line,
                            selected: current == path,
                            onTap: () => _choose(home, path),
                          ),
                          const SizedBox(height: Spacing.smMd),
                        ],
                      ],
                    ),
                  ),
                  // B7 review M-4: a switch in flight shows (taps wait);
                  // not under its own confirmation sheet.
                  if (_busy && (ModalRoute.isCurrentOf(context) ?? true)) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: Spacing.sm),
                  ],
                  const SizedBox(height: Spacing.sm),
                  Text(
                    loc.flow_howFooter,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
    );
  }
}
