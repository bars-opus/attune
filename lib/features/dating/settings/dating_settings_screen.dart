// Spec 2 §3.12 (W3a shell; W3c adds the rest): Dating settings. W3a: the
// Dating lock (Spec 1's setting, R-8), "Tell me when Dating opens" while
// asked for, and the gentle-wait reflection's clear in every state (carry
// 5; exposure-reducing, never gated). Large text through AllowLargeText;
// InfoRowWidget scales by itself.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show setDatingLockInDating;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart'
    show datingStepLocation;
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart'
    show DatingLoadError;
import 'package:attune/features/dating/setup/ready_step.dart'
    show datingDropTimeLabel, datingDropTimeOf, pickDatingDropTime;
import 'package:go_router/go_router.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingSettingsScreen extends ConsumerStatefulWidget {
  const DatingSettingsScreen({super.key});

  @override
  ConsumerState<DatingSettingsScreen> createState() =>
      _DatingSettingsScreenState();
}

class _DatingSettingsScreenState extends ConsumerState<DatingSettingsScreen> {
  bool _clearing = false;
  GentleWaitSave? _cleared;
  final _keys = DatingActionKeys();
  bool _lifeBusy = false;
  bool _paused = false;
  DatingLifecycleError? _lifeError;
  DatingWrite? _saveFailed;

  /// Final fix (M-4): the writes on their way, one per action, so a fast
  /// on/off double toggle sends one write and the order can't decide.
  final _saving = <String>{};

  @override
  void initState() {
    super.initState();
    // D8: another account on the phone sees nothing of this one's
    // answers (its reads are its own provider entries).
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _clearing = false;
        _cleared = null;
        _cancelling = false;
        _cancelled = null;
        _lifeBusy = false;
        _paused = false;
        _lifeError = null;
        _saveFailed = null;
        _saving.clear();
      });
    });
  }

  String? get _account => ref.read(datingAccountProvider);

  Future<void> _save(String action, Map<String, Object> values) async {
    if (!_saving.add(action)) return;
    try {
      final account = _account;
      setState(() => _saveFailed = null);
      final w = await ref
          .read(datingSetupGatewayProvider)
          .saveSettings(_keys.keyFor(action, '$account|$values'), values);
      // Carry A: a final answer drops the key; busy or failed keeps it.
      _keys.settle(action, reason: w.reason);
      if (!mounted || _account != account) return;
      if (!w.ok) setState(() => _saveFailed = w);
      ref.invalidate(datingMyProfileProvider(account));
      if (values.containsKey('drop_time')) {
        ref.invalidate(datingHomeProvider(account));
      }
    } finally {
      _saving.remove(action);
    }
  }

  Future<void> _changeTime(String current) async {
    final picked = await pickDatingDropTime(context, current);
    if (picked != null && picked != current && mounted) {
      await _save('time', {'drop_time': picked});
    }
  }

  /// R-40: the step comes back here when it saves.
  /// Task 11's `from` allowlist builds the link.
  void _open(String step) =>
      context.push(datingStepLocation('$step?from=settings')!);

  Future<void> _push(String key, bool on) async {
    if (on && !ref.read(pushAskerProvider).permissionGranted) {
      final outcome = await ref
          .read(pushAskerProvider)
          .askInContext(PushAskContext.j3);
      if (outcome != PushAskOutcome.granted || !mounted) return;
    }
    await _save(key, {key: on});
  }

  Future<void> _photosAfter(bool on) async {
    if (!_saving.add('after')) return;
    try {
      final account = _account;
      setState(() => _saveFailed = null);
      final w = await ref
          .read(datingPhotosGatewayProvider)
          .photosAfterMutual(_keys.keyFor('after', '$account|$on'), on);
      _keys.settle('after', reason: w.reason);
      if (!mounted || _account != account) return;
      if (!w.ok) setState(() => _saveFailed = w);
      ref.invalidate(datingPhotosProvider(account));
    } finally {
      _saving.remove('after');
    }
  }

  Future<void> _lifecycle(bool pause) async {
    if (_lifeBusy) return;
    final account = _account;
    final action = pause ? 'pause' : 'resume';
    setState(() {
      _lifeBusy = true;
      _lifeError = null;
      _paused = false;
    });
    final life = ref.read(datingLifecycleGatewayProvider);
    final key = _keys.keyFor(action, account ?? '');
    final r = pause ? await life.pause(key) : await life.resume(key);
    // Carry A (T1 I-1): every answer settles, so Pause, Resume, Pause on
    // one screen are three requests; busy or failed keeps the key.
    _keys.settle(action, error: r.error);
    if (!mounted || _account != account) return;
    final error = r.error;
    setState(() {
      _lifeBusy = false;
      // Already resumed elsewhere: read the home again (as the section).
      _lifeError = error == DatingLifecycleError.notPaused ? null : error;
      _paused = pause && r.ok;
    });
    if (r.ok || error == DatingLifecycleError.notPaused) {
      ref.invalidate(datingHomeProvider(account));
    }
  }

  bool _cancelling = false;
  DatingNoticeResult? _cancelled;

  Future<void> _clearReflection() async {
    if (_clearing) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _clearing = true;
      _cleared = null;
    });
    var result = GentleWaitSave.failed;
    try {
      result = await ref.read(gentleWaitGatewayProvider).clear();
    } catch (_) {
      result = GentleWaitSave.failed;
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _clearing = false;
      _cleared = result;
    });
  }

  /// Fix round 1 (Minor 5): never silent. Busy and failed say so and the
  /// row stays on; the switch waits while the cancel runs. Offline it
  /// stays enabled (exposure-reducing, never gated) and says why if it
  /// fails.
  Future<void> _cancelNotice() async {
    if (_cancelling) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _cancelling = true;
      _cancelled = null;
    });
    final result = await ref.read(datingHomeGatewayProvider).cancelNotice();
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _cancelling = false;
      _cancelled = result;
    });
    if (result == DatingNoticeResult.saved) {
      ref.invalidate(datingHomeProvider(account));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final homeRead = ref.watch(
      datingHomeProvider(ref.watch(datingAccountProvider)),
    );
    final home = homeRead.valueOrNull;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;
    final account = ref.watch(datingAccountProvider);
    final hasProfile = home?.hasProfile ?? false;
    final profileRead =
        hasProfile ? ref.watch(datingMyProfileProvider(account)) : null;
    // Final fix (M-5): a failed read says so (never a made-up 19:00 or a
    // blank Ages); M-6: the profile rows only once the read says there is
    // a profile (a gentle wait may have none yet).
    final profileFailed = profileRead?.hasError ?? false;
    final profile = profileFailed ? null : profileRead?.valueOrNull;
    final showRows = profile?.exists ?? false;
    final photos =
        hasProfile
            ? ref.watch(datingPhotosProvider(account)).valueOrNull
            : null;
    final from = photos?.afterMutualFrom;
    final afterOpen = from != null && !DateTime.now().toUtc().isBefore(from);
    final time = datingDropTimeOf(profile);
    final granted = ref.watch(pushAskerProvider).permissionGranted;
    // Fix 1 (M-5): an icon, so the titles line up with the rows'.
    Widget toggle(
      IconData icon,
      String title,
      String? subtitle,
      bool value,
      ValueChanged<bool>? onChanged,
    ) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: online ? onChanged : null,
    );
    // Carry C: pausing and leaving reduce exposure, so they are never
    // gated offline (deletion is never blocked); everything else needs
    // the connection.
    Widget row(
      String title,
      String subtitle,
      IconData icon,
      VoidCallback onTap, {
      bool evenOffline = false,
    }) => InfoRowWidget(
      title: title,
      subtitle: subtitle,
      icon: icon,
      showAvatar: false,
      // A one-line row is 42 dp; this keeps every target at 48 or more.
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      onTap: online || evenOffline ? onTap : null,
    );
    Widget calm(String text) => Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Text(text, style: theme.textTheme.bodyMedium),
      ),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_settingsTitle)),
        body: SafeArea(
          // Not a lazy list: every row is built, so Leave and Clear are
          // always in the tree to scroll to (C-2).
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!online) calm(loc.dating_offline),
                if (profileFailed)
                  DatingLoadError(
                    busy: profileRead!.isLoading,
                    onRetry:
                        () => ref.invalidate(datingMyProfileProvider(account)),
                  ),
                // §3.12, in its order (W3c; Other countries and Never
                // introduce me are W5c's, App icon W8b's).
                if (showRows) ...[
                  row(
                    loc.dating_settingsTime,
                    datingDropTimeLabel(time),
                    Icons.schedule,
                    () => _changeTime(time),
                  ),
                  row(
                    loc.dating_settingsWho,
                    '',
                    Icons.people_outline,
                    () => _open('meet'),
                  ),
                  row(
                    loc.dating_settingsAges,
                    profile?.minAge != null && profile?.maxAge != null
                        ? loc.dating_settingsAgesValue(
                          profile!.minAge!,
                          profile.maxAge!,
                        )
                        : '',
                    Icons.cake_outlined,
                    () => _open('meet'),
                  ),
                  row(
                    loc.dating_settingsHowFar,
                    '',
                    Icons.near_me_outlined,
                    () => _open('where'),
                  ),
                  toggle(
                    Icons.photo_outlined,
                    loc.dating_settingsPhotosAfter,
                    afterOpen || from == null
                        ? null
                        : loc.dating_photosAfterMutualFrom(
                          MyDateFormat.toDate(from.toLocal()),
                        ),
                    photos?.afterMutual ?? false,
                    afterOpen ? _photosAfter : null,
                  ),
                  toggle(
                    Icons.data_saver_on_outlined,
                    loc.dating_settingsDataSaver,
                    loc.dating_settingsDataSaverSub,
                    profile?.dataSaver ?? false,
                    (on) => _save('saver', {'data_saver': on}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Semantics(
                      header: true,
                      child: Text(
                        loc.dating_settingsNotifications,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  toggle(
                    Icons.notifications_none,
                    loc.dating_pushDigest,
                    null,
                    granted && (profile?.digestPush ?? false),
                    (on) => _push('digest_push', on),
                  ),
                  toggle(
                    Icons.chat_bubble_outline,
                    loc.dating_pushMessages,
                    null,
                    granted && (profile?.chatPush ?? true),
                    (on) => _push('chat_push', on),
                  ),
                  // Never silent: busy is calm, anything else says so.
                  if (_saveFailed?.reason == 'busy')
                    DatingCalmLine(loc.dating_busy)
                  else if (_saveFailed != null)
                    FlowErrorLine(
                      text: loc.dating_errorGeneric,
                      liveRegion: true,
                    ),
                ],
                // Switches are SwitchListTiles: the title is the switch's own
                // semantic label and a tap anywhere on the row toggles it.
                if (home?.notice.requested ?? false)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.notifications_none),
                    title: Text(loc.dating_settingsNotice),
                    value: true,
                    onChanged:
                        _cancelling
                            ? null
                            : (on) {
                              if (!on) _cancelNotice();
                            },
                  ),
                if (_cancelled == DatingNoticeResult.busy)
                  calm(loc.dating_busy),
                if (_cancelled != null &&
                    _cancelled != DatingNoticeResult.saved &&
                    _cancelled != DatingNoticeResult.busy)
                  FlowErrorLine(
                    text: online ? loc.dating_errorGeneric : loc.dating_offline,
                    liveRegion: true,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(loc.flow_lockTitle),
                  subtitle: Text(loc.flow_lockSubtitle),
                  value: lock,
                  onChanged: (on) => setDatingLockInDating(context, ref, on),
                ),
                InfoRowWidget(
                  key: const ValueKey('dating_settings_clear_reflection'),
                  title: loc.dating_settingsClearReflection,
                  subtitle: '',
                  icon: Icons.delete_outline,
                  showAvatar: false,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  onTap: _clearing ? null : _clearReflection,
                ),
                if (_cleared == GentleWaitSave.saved)
                  calm(loc.dating_gentleWaitCleared),
                if (_cleared == GentleWaitSave.busy)
                  calm(loc.dating_gentleWaitClearBusy),
                if (_cleared != null &&
                    _cleared != GentleWaitSave.saved &&
                    _cleared != GentleWaitSave.busy)
                  FlowErrorLine(
                    text: loc.dating_errorGeneric,
                    liveRegion: true,
                  ),
                if (home?.state == DatingHomeState.active ||
                    home?.state == DatingHomeState.coolOff)
                  row(
                    loc.dating_settingsPause,
                    '',
                    Icons.pause_circle_outline,
                    () => _lifecycle(true),
                    evenOffline: true,
                  ),
                // Carry B: the section's own rule (a shared space, travel, a
                // parked number or a same-gender switch keep it paused).
                if (home?.resumeOffered ?? false)
                  row(
                    loc.dating_settingsResume,
                    '',
                    Icons.play_circle_outline,
                    () => _lifecycle(false),
                  ),
                if (_paused) DatingCalmLine(loc.dating_pausedLine),
                // Fix 1 (M-2): offline, the line at the top already says why.
                if (_lifeError != null &&
                    !(_lifeError == DatingLifecycleError.failed && !online))
                  ...datingLifecycleErrorRows(context, loc, _lifeError!),
                // R-41, C-2: never blocked by state; with no Dating data at
                // all (not started, nothing saved) there is nothing to leave.
                // Carry C: an unreadable home (offline, busy) still offers
                // it, and it is never gated offline.
                if ((homeRead.hasError && home == null) ||
                    (home != null &&
                        (home.hasData ||
                            home.state != DatingHomeState.notStarted)))
                  row(
                    loc.dating_settingsLeave,
                    '',
                    Icons.logout,
                    () => context.push(DatingPaths.leave),
                    evenOffline: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
