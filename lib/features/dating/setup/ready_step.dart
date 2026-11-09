// Spec 2 §3.2 D13 (Step 12 of 12): the first drop and its time (07:00-22:00,
// 30-minute steps, a labelled list), one item while you wait (R-39), the
// shared-phone question (S17: Spec 1's Dating lock, the PIN set up first;
// the existing every-open PIN), and Done -> activate_dating_profile, then Me.
// The plain-icon offer stays hidden until W8b (A-11). No motion (§3.15).
//
// T11 carries: activation settles its key once the answer is final (carry
// A: a named refusal gives the next Done a new key; busy or failed keeps
// it, so the retry is the same request); every refusal is the lifecycle
// rows' own copy (carry B); one Done, one lock change and one every-open
// change at a time (carry C); another account sees none of the last one's
// answers, refusal or first drop (D8).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/card/dating_card.dart'
    show DatingStartLink;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show setDatingLockInDating;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.2 D13: 07:00 to 22:00 in 30-minute steps.
final datingDropTimes = [
  for (var m = 7 * 60; m <= 22 * 60; m += 30)
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
];

/// '19:30' (or the server's '19:30:00') in the person's clock format.
String datingDropTimeLabel(String hhmm) {
  final parts = hhmm.split(':');
  return MyDateFormat.toTime(
    DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1])),
  );
}

String datingDropTimeOf(DatingMyProfile? p) {
  final t = p?.dropTime;
  return t != null &&
          t.length >= 5 &&
          datingDropTimes.contains(t.substring(0, 5))
      ? t.substring(0, 5)
      : '19:00';
}

Future<String?> pickDatingDropTime(BuildContext context, String current) {
  final loc = AppLocalizations.of(context)!;
  return showDatingPicker<String>(
    context,
    title: loc.dating_readyTimeTitle,
    items: [for (final t in datingDropTimes) (t, datingDropTimeLabel(t))],
    selected: current,
  );
}

class DatingReadyStep extends ConsumerStatefulWidget {
  const DatingReadyStep({super.key, required this.nav, this.pins});

  final DatingStepNav nav;
  final SafetyPinStore? pins;

  @override
  ConsumerState<DatingReadyStep> createState() => _DatingReadyStepState();
}

class _DatingReadyStepState extends ConsumerState<DatingReadyStep>
    with DatingStepState<DatingReadyStep> {
  bool? _shared;
  bool _everyOpen = false;
  bool _activating = false;
  bool _pinBusy = false;
  DatingLifecycleError? _error;

  SafetyPinStore get _pins => widget.pins ?? SafetyPinStore.instance;

  @override
  void initState() {
    super.initState();
    _pins
        .everyOpen()
        .then((on) {
          if (mounted) setState(() => _everyOpen = on);
        })
        .catchError((Object _) {});
  }

  @override
  void resetAnswers() {
    _shared = null;
    _activating = false;
    // _pinBusy stays (M-1): a PIN change still open ends in its own
    // finally, and none other starts before it does.
    _error = null;
  }

  @override
  void seedAnswers(DatingMyProfile profile) {}

  Future<void> _changeTime(String current) async {
    final picked = await pickDatingDropTime(context, current);
    if (picked == null || picked == current || !mounted) return;
    await write(
      'd13time',
      picked,
      (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
        'drop_time': picked,
      }),
      (_) {
        ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));
      },
    );
  }

  /// One PIN change at a time: a second tap while the PIN is asked or
  /// set changes nothing.
  Future<void> _guarded(Future<void> Function() change) async {
    if (_pinBusy) return;
    setState(() => _pinBusy = true);
    try {
      await change();
    } catch (_) {
      // The keystore refused: the switch stays as it was.
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }

  Future<void> _setEveryOpen(bool on) => _guarded(() async {
    if (on) {
      if (!await _pins.hasPin()) {
        if (!mounted) return;
        await context.push(RouteNames.safetyPin);
        if (!await _pins.hasPin()) return;
      }
    } else {
      if (!mounted) return;
      if (!await confirmSafetyPin(context, store: _pins)) return;
    }
    await _pins.setEveryOpen(on);
    if (mounted) setState(() => _everyOpen = on);
  });

  Future<void> _done() async {
    if (_activating || saving) return;
    final account = ref.read(datingAccountProvider);
    final keys = this.keys;
    setState(() {
      _activating = true;
      _error = null;
    });
    DatingLifecycleResult r;
    try {
      r = await ref
          .read(datingLifecycleGatewayProvider)
          .activate(keys.keyFor('activate', account ?? ''));
    } catch (_) {
      // The repository answers rather than throws; anything else is
      // failed (the key kept), never the error's text.
      r = const DatingLifecycleResult.refused(DatingLifecycleError.failed);
    }
    // Carry A: a final answer drops the key; busy or failed keeps it.
    keys.settle('activate', error: r.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _activating = false;
      _error = r.error;
    });
    if (r.ok) {
      ref.invalidate(datingHomeProvider(account));
      widget.nav.toMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final profile = watchProfile();
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final drop =
        ref
            .watch(datingHomeProvider(account))
            .valueOrNull
            ?.firstDropAt
            ?.toLocal();
    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;
    final current = datingDropTimeOf(profile);
    return DatingStepFrame(
      step: 'ready',
      title: loc.dating_readyTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profileFailed)
            DatingLoadError(busy: profileRetrying, onRetry: retryProfile),
          if (drop != null)
            Text(
              loc.dating_readyFirst(
                MyDateFormat.toDate(drop),
                MyDateFormat.toTime(drop),
              ),
              style: theme.textTheme.bodyLarge,
            ),
          // M-4: off (and read as off) offline, while a save runs and while
          // Done is activating (a new time never races activation).
          DatingStartLink(
            label: loc.dating_readyChangeTime,
            onPressed:
                online && !saving && !_activating
                    ? () => _changeTime(current)
                    : null,
          ),
          if (refusal != null) datingRefusalLine(loc, refusal!),
          const SizedBox(height: Spacing.md),
          Semantics(
            header: true,
            child: Text(
              loc.dating_readyWhile,
              style: theme.textTheme.titleSmall,
            ),
          ),
          DatingStartLink(
            label: loc.dating_readyJournal,
            onPressed: () => context.push(RouteNames.reflectionJournal),
          ),
          const SizedBox(height: Spacing.md),
          DatingChoiceGroup<bool>(
            label: loc.dating_readySharedQ,
            options: [(true, loc.dating_yes), (false, loc.dating_no)],
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
          ),
          if (_shared == true) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_readyLock),
              value: lock,
              onChanged:
                  (on) => _guarded(
                    () => setDatingLockInDating(
                      context,
                      ref,
                      on,
                      pins: widget.pins,
                    ),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_readyEveryOpen),
              value: _everyOpen,
              onChanged: _setEveryOpen,
            ),
          ],
          // A-11: "Some people like their apps to look plain." arrives with
          // Settings -> App icon in W8b.
          if (_error != null)
            ...datingLifecycleErrorRows(
              context,
              loc,
              _error!,
              // M-5: D11 goes back to this D13 instead of walking on.
              onVerify: () => widget.nav.next('verify?from=ready'),
            ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_done,
        busy: _activating,
        onPressed: online ? _done : null,
      ),
    );
  }
}
