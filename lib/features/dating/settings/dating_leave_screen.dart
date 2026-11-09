// Spec 2 §3.8 (carries 12, 13): Leave Dating and delete my data. One exit
// v2 call (one hard delete; the never-introduce list kept only if ticked,
// off by default). Never blocked by state; a restricted account's exit is
// `suspended`, which reads "You've left Dating." alone. No motion.
//
// T12 carries: every answer settles its key (A), so a deliberate second
// tap is a new request and a busy or failed one is the same; leaving and
// pausing are never gated offline (C, R-48: deletion is never blocked),
// the offline line says so before the tap and the button stays; another
// account on the phone sees nothing of this one (D8). Fix 1: Pause instead
// only where settings offers Pause (R-41), "paused" only for a paused
// answer, and a restricted, held or unread home never reads "set it up
// again" (I-1, I-2).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _Outcome { left, leftSuspended, paused }

const _held = {
  DatingHomeState.restricted,
  DatingHomeState.hold,
  DatingHomeState.ageReview,
};

class DatingLeaveScreen extends ConsumerStatefulWidget {
  const DatingLeaveScreen({super.key});

  @override
  ConsumerState<DatingLeaveScreen> createState() => _DatingLeaveScreenState();
}

class _DatingLeaveScreenState extends ConsumerState<DatingLeaveScreen> {
  var _keys = DatingActionKeys();
  bool _keepList = false;
  bool _busy = false;
  DatingLifecycleError? _error;
  _Outcome? _outcome;

  @override
  void initState() {
    super.initState();
    // D8: another account starts from nothing (its own keys too).
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _keys = DatingActionKeys();
        _keepList = false;
        _busy = false;
        _error = null;
        _outcome = null;
      });
    });
  }

  Future<void> _run(String action) async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    final keys = _keys;
    // Fix 1 (I-2, R-41): a restricted, held or age-review home, or one
    // that couldn't be read, never reads "set it up again" (exit answers
    // `suspended` only for a restriction-table hold).
    final read = ref.read(datingHomeProvider(account));
    final known = read.hasError ? null : read.valueOrNull;
    final held = known == null || _held.contains(known.state);
    setState(() {
      _busy = true;
      _error = null;
    });
    final life = ref.read(datingLifecycleGatewayProvider);
    final key = keys.keyFor(action, '$account|$_keepList');
    final r =
        action == 'exit'
            ? await life.exit(key, keepNeverIntroduce: _keepList)
            : await life.pause(key);
    // Carry A: a final answer drops the key; busy or failed keeps it.
    keys.settle(action, error: r.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _error = r.error;
      if (r.ok) {
        // Fix 1 (I-1): "paused" only when the server says so; any other
        // answer is read again from the home, never claimed.
        _outcome =
            action == 'pause'
                ? (r.state == 'paused' ? _Outcome.paused : null)
                : (r.state == 'suspended' || held
                    ? _Outcome.leftSuspended
                    : _Outcome.left);
      }
    });
    if (r.ok) ref.invalidate(datingHomeProvider(account));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final homeRead = ref.watch(
      datingHomeProvider(ref.watch(datingAccountProvider)),
    );
    final state = homeRead.hasError ? null : homeRead.valueOrNull?.state;
    // Fix 1 (I-1, R-41): Pause only where a pause can happen, as settings.
    final canPause =
        state == DatingHomeState.active || state == DatingHomeState.coolOff;
    final outcome = _outcome;
    final error = _error;
    // Final fix (M-15, §3.15): what goes and what is kept are read as list
    // items, each one node with its bullet (as D1's numbered items).
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: theme.textTheme.bodyLarge),
            Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          ],
        ),
      ),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_leaveTitle)),
        body: SafeArea(
          // Not a lazy list: both buttons are always built (and reachable).
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (outcome != null) ...[
                  DatingCalmLine(switch (outcome) {
                    _Outcome.left => loc.dating_leftDone,
                    _Outcome.leftSuspended => loc.dating_leftSuspended,
                    _Outcome.paused => loc.dating_pausedLine,
                  }),
                  FlowPrimaryButton(
                    label: loc.dating_done,
                    onPressed: () => context.go(homeLocation(tab: AppTab.me)),
                  ),
                ] else ...[
                  // R-48: never gated offline; said once, before the tap.
                  if (!online) DatingCalmLine(loc.dating_offline),
                  line(loc.dating_leaveNow),
                  line(loc.dating_leave30),
                  line(loc.dating_leaveSafety),
                  line(loc.dating_leaveRecord),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(loc.dating_leaveKeepList),
                    value: _keepList,
                    onChanged:
                        _busy
                            ? null
                            : (v) => setState(() => _keepList = v ?? false),
                  ),
                  // Offline, the line above already says why it failed.
                  if (error != null &&
                      !(error == DatingLifecycleError.failed && !online))
                    ...datingLifecycleErrorRows(context, loc, error),
                  const SizedBox(height: Spacing.md),
                  FlowPrimaryButton(
                    label: loc.dating_leaveConfirm,
                    busy: _busy,
                    onPressed: () => _run('exit'),
                  ),
                  if (canPause)
                    FlowSecondaryButton(
                      label: loc.dating_leavePause,
                      onPressed: !_busy ? () => _run('pause') : null,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
