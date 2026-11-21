// Spec 2 W6c (§3.6 meeting kit, §3.15 Meeting kit; S21): Plan a meet. A
// reviewed checklist; "When?" and "Where?" held in memory only (never on
// the server, never on disk: quick exit and sign-out forget them); Share
// my plan through the system share sheet and Send as text message, both
// with the plan's words and never the match's name or photo; Check on me
// schedules one neutral push three hours after the meet (the only server
// row: a time and a route). Nothing here moves; Share works offline,
// Check on me needs a connection.
//
// Task 10 rulings: a new When after Check on me offers Check on me again
// (the server replaces the last one, R-46); the date and time pickers
// close, choosing nothing, once the signed-in account changes (D8); a
// refused check-in says why (invalid; rate_limited; anything else, closed
// included, the general line).
//
// Fix round 1: the kit reads the person's own pending check-in from the
// server when it opens, comes online or changes account (I-1; memory is
// only the fallback while it can't be read), shows it with its day and
// drops it once its time has passed (I-2), and says plainly when no push
// can reach this phone (I-3); the share sheet opens from the tapped
// button and a failure says so (I-5); the date picker offers only days
// whose every time is inside the server's window (M-2); Check on me says
// when it needs a connection (M-4) and shows its progress (M-5).
//
// Final client fix wave: an answer that lands after quick exit or sign-out
// wiped the plan (a check-in read, Check on me) never writes it back (M-2:
// the wipe moves a generation the kit holds); a remembered meet time that
// has passed is dropped when the kit opens (M-4).
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart'
    show oneSignalServiceProvider;
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// §3.6: the check-in comes three hours after the meet.
const kDatingCheckinAfter = Duration(hours: 3);

/// The server's window for a check-in (schedule_dating_checkin).
const kDatingCheckinSoonest = Duration(minutes: 5);
const kDatingCheckinLatest = Duration(days: 7);

/// Whether a check-in for a meet at [meet] is inside the server's window.
bool datingCheckinInWindow(DateTime meet, DateTime now) {
  final at = meet.add(kDatingCheckinAfter);
  return at.isAfter(now.add(kDatingCheckinSoonest)) &&
      !at.isAfter(now.add(kDatingCheckinLatest));
}

/// M-2: the last day the date picker offers: the last day whose every
/// time still has its check-in inside the window.
DateTime datingPlanLastDay(DateTime now) {
  final latest = now.add(kDatingCheckinLatest - kDatingCheckinAfter);
  final day = DateTime(latest.year, latest.month, latest.day);
  final endOfDay = DateTime(day.year, day.month, day.day, 23, 59);
  return endOfDay.isAfter(latest)
      ? DateTime(day.year, day.month, day.day - 1)
      : day;
}

/// The plan in memory only (D20): read by Get help's message, forgotten by
/// quick exit and sign-out (Dating's wipe entry) and by another account.
/// [checkinAt] is the last check-in this account set or read; the server's
/// row is the truth, and the kit reads it whenever it can.
abstract final class DatingPlanMemory {
  static String? place;
  static DateTime? at;
  static String? account;
  static DateTime? checkinAt;

  /// M-2: moved by every [clear]. A kit writes only under the generation
  /// it holds, so nothing written after a wipe brings the plan back.
  static int generation = 0;

  static Future<void> clear() async {
    generation++;
    place = null;
    at = null;
    account = null;
    checkinAt = null;
  }
}

/// The phone's clock (tests fix it).
final datingNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Fix round 2: this phone's push state, known only once the SDK has
/// started and, when notifications are allowed, holds a device token:
/// false (notifications off), true (allowed, with a token), null (not
/// known yet: the no-push line waits).
bool? datingPushState({
  required bool started,
  required bool granted,
  required String? token,
}) {
  if (!started) return null;
  if (!granted) return false;
  return token == null ? null : true;
}

/// I-3: whether this phone can show Attune's notifications (tests replace).
final datingPushAllowedProvider = Provider<bool? Function()>((ref) {
  return () {
    final push = ref.read(oneSignalServiceProvider);
    return datingPushState(
      started: push.sdkStarted,
      granted: push.permissionGranted,
      token: push.currentSubscriptionId,
    );
  };
});

/// The system share sheet, opened from [origin] (the tapped button: an
/// iPad needs it). Throws when it can't open (tests replace it).
final datingShareProvider =
    Provider<Future<void> Function(String text, Rect? origin)>(
      (ref) => (text, origin) => Share.share(text, sharePositionOrigin: origin),
    );

/// Opens a link; false when nothing opened it (tests replace it).
final datingLaunchProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  },
);

/// The `sms:` link for [body]: percent-encoded (a query built from
/// queryParameters turns spaces into "+", which Messages shows as is).
Uri datingSmsUri(String body) =>
    Uri(scheme: 'sms', query: 'body=${Uri.encodeComponent(body)}');

/// A text message the person sends themselves. Where nothing opens it (a
/// tablet with no messages app), the share sheet offers the same words,
/// from [origin]. Nothing is ever sent by itself. Throws when neither
/// opens.
final datingSmsProvider =
    Provider<Future<void> Function(String body, Rect? origin)>(
      (ref) => (body, origin) async {
        if (await ref.read(datingLaunchProvider)(datingSmsUri(body))) return;
        await ref.read(datingShareProvider)(body, origin);
      },
    );

/// I-5: [context]'s box on the screen (the share sheet's anchor).
Rect? datingOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The plan's words: never the match's name or photo.
String datingPlanText(AppLocalizations loc, DateTime at, String place) =>
    loc.dating_planShareText(
      MyDateFormat.toDate(at),
      MyDateFormat.toTime(at),
      place,
      MyDateFormat.toTime(at.add(kDatingCheckinAfter)),
    );

class DatingPlanMeetScreen extends ConsumerStatefulWidget {
  const DatingPlanMeetScreen({super.key, required this.matchId, this.now});

  final String matchId;
  final DateTime Function()? now;

  @override
  ConsumerState<DatingPlanMeetScreen> createState() =>
      _DatingPlanMeetScreenState();
}

class _DatingPlanMeetScreenState extends ConsumerState<DatingPlanMeetScreen> {
  final _place = TextEditingController();
  DateTime? _at;
  DateTime? _checkinAt;

  /// I-3: whether a push can reach this person (the server's last word).
  bool _push = true;
  String? _reason;
  bool _scheduling = false;
  bool _cancelling = false;

  /// I-1: each read's ticket; a read answered after a newer one, or after
  /// an account change, is dropped.
  int _readTicket = 0;

  /// Fix round 2: the last read online failed (Cancel and Try again show).
  bool _readFailed = false;

  /// M-2: the plan memory's generation this kit writes under (taken when
  /// it opens and after its own clear on another account).
  late int _generation;

  /// The date and time pickers opened here (D8: closed once the account
  /// changes). A set: a picker on its way out rebuilds after the next one
  /// has opened.
  final _pickers = <Route<dynamic>>{};

  DateTime get _now {
    final DateTime Function() clock = widget.now ?? ref.read(datingNowProvider);
    return clock();
  }

  @override
  void initState() {
    super.initState();
    final account = ref.read(datingAccountProvider);
    if (DatingPlanMemory.account == account) {
      _place.text = DatingPlanMemory.place ?? '';
      _at = DatingPlanMemory.at;
      _checkinAt = DatingPlanMemory.checkinAt;
      // M-4: a meet that has passed is not offered again.
      if (_at != null && _at!.isBefore(_now)) {
        _at = null;
        DatingPlanMemory.at = null;
      }
    } else {
      unawaited(DatingPlanMemory.clear());
    }
    _generation = DatingPlanMemory.generation;
    _place.addListener(_remember);
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _closePicker();
      setState(() {
        // The time first: clearing the place remembers what is left.
        _at = null;
        _checkinAt = null;
        _push = true;
        _readFailed = false;
        _place.text = '';
        _reason = null;
        _scheduling = false;
        _cancelling = false;
      });
      unawaited(DatingPlanMemory.clear());
      _generation = DatingPlanMemory.generation;
      unawaited(_readCheckin());
    });
    // I-1: read again when the connection comes back.
    ref.listenManual<AsyncValue<bool>>(datingOnlineProvider, (previous, next) {
      if (next.valueOrNull == true && previous?.valueOrNull != true) {
        unawaited(_readCheckin());
      }
    });
    unawaited(_readCheckin());
  }

  /// I-1: the server's pending check-in for this account, read when the kit
  /// opens online, when the connection comes back and on another account
  /// (memory stays the fallback when it can't be read).
  Future<void> _readCheckin() async {
    final account = ref.read(datingAccountProvider);
    if (account == null) return;
    // Only online (the connection's return reads again, above).
    if (ref.read(datingOnlineProvider).valueOrNull != true) return;
    final ticket = ++_readTicket;
    final r = await ref.read(datingChatGatewayProvider).checkin();
    if (!mounted || ticket != _readTicket) return;
    if (ref.read(datingAccountProvider) != account) return;
    if (!r.known) {
      setState(() => _readFailed = true);
      return;
    }
    setState(() {
      _readFailed = false;
      _checkinAt = r.at?.toLocal();
      _push = r.push;
      _remember();
    });
  }

  /// M-2: whether the plan memory is still the one this kit writes to
  /// (no wipe since).
  bool get _current => DatingPlanMemory.generation == _generation;

  void _remember() {
    if (!_current) return;
    DatingPlanMemory.account = ref.read(datingAccountProvider);
    DatingPlanMemory.place =
        _place.text.trim().isEmpty ? null : _place.text.trim();
    DatingPlanMemory.at = _at;
    DatingPlanMemory.checkinAt = _checkinAt;
  }

  void _closePicker() {
    for (final route in _pickers.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _pickers.clear();
  }

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  /// D8: the picker's route, so another account closes it.
  Widget _tracked(BuildContext context, Widget? child) {
    final route = ModalRoute.of(context);
    if (route != null) _pickers.add(route);
    return DatingSheetTracker(child: child!);
  }

  Future<void> _pickWhen() async {
    final account = ref.read(datingAccountProvider);
    final now = _now;
    final first = DateTime(now.year, now.month, now.day);
    final last = datingPlanLastDay(now);
    final was = _at;
    final initial =
        was == null || was.isBefore(first) || was.isAfter(last) ? first : was;
    final day = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      currentDate: now,
      routeSettings: datingSheetSettings('plan-date'),
      builder: _tracked,
    );
    if (day == null || !mounted) return;
    if (ref.read(datingAccountProvider) != account) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(was ?? now),
      routeSettings: datingSheetSettings('plan-time'),
      builder: _tracked,
    );
    if (time == null || !mounted) return;
    if (ref.read(datingAccountProvider) != account) return;
    setState(() {
      _at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _reason = null;
      _remember();
    });
  }

  String? get _text {
    final at = _at;
    final place = _place.text.trim();
    if (at == null || place.isEmpty) return null;
    return datingPlanText(AppLocalizations.of(context)!, at, place);
  }

  /// I-5: the share sheet or the text message, from the tapped button; a
  /// failure says so (nothing was shared).
  Future<void> _send(
    BuildContext button,
    Future<void> Function(String text, Rect? origin) send,
    String text,
  ) async {
    final origin = datingOriginOf(button);
    try {
      await send(text, origin);
    } catch (_) {
      if (mounted) setState(() => _reason = 'share_failed');
    }
  }

  Future<void> _checkOnMe() async {
    final at = _at;
    if (at == null || _scheduling) return;
    // The scope outlives the kit: what the server did is kept even if the
    // kit has gone by the answer (I-1).
    final scope = ProviderScope.containerOf(context, listen: false);
    final account = scope.read(datingAccountProvider);
    final generation = _generation;
    setState(() => _scheduling = true);
    final when = at.add(kDatingCheckinAfter);
    final r = await scope.read(datingChatGatewayProvider).scheduleCheckin(when);
    if (scope.read(datingAccountProvider) != account) return;
    // M-2: wiped meanwhile: nothing is written back.
    if (r.ok && DatingPlanMemory.generation == generation) {
      DatingPlanMemory.account = account;
      DatingPlanMemory.checkinAt = when;
    }
    if (!mounted) return;
    _readTicket++;
    setState(() {
      _scheduling = false;
      // A refusal leaves the last one as the server keeps it.
      if (r.ok) {
        _readFailed = false;
        _checkinAt = when;
        _push = r.push ?? _push;
      }
      _reason = r.ok ? null : r.reason;
      _remember();
    });
  }

  Future<void> _cancelCheckin() async {
    if (_cancelling) return;
    final scope = ProviderScope.containerOf(context, listen: false);
    final account = scope.read(datingAccountProvider);
    setState(() => _cancelling = true);
    final r = await scope.read(datingChatGatewayProvider).cancelCheckin();
    if (scope.read(datingAccountProvider) != account) return;
    if (r.ok) DatingPlanMemory.checkinAt = null;
    if (!mounted) return;
    _readTicket++;
    setState(() {
      _cancelling = false;
      if (r.ok) {
        _checkinAt = null;
        _readFailed = false;
      }
      _reason = r.ok ? null : r.reason;
      _remember();
    });
  }

  String _refusal(AppLocalizations loc, String reason) => switch (reason) {
    'rate_limited' => loc.dating_errorRateLimited,
    'invalid' => loc.dating_planCheckinInvalid,
    _ => loc.dating_errorGeneric,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final now = _now;
    final text = _text;
    final at = _at;
    // I-2: a check-in whose time has passed is no longer shown.
    final checkin =
        _checkinAt != null && _checkinAt!.isAfter(now) ? _checkinAt : null;
    // I-3: no push can reach this phone (or any device of theirs).
    // Fix round 2: this phone's state counts only once it is known.
    final unreachable =
        !_push || ref.read(datingPushAllowedProvider)() == false;
    // Fix round 2: a failed read offers Cancel even with nothing known.
    final unknown = _readFailed && online;
    // M-2: a meet whose check-in falls outside the server's window says
    // so before anything is asked.
    final inWindow = at != null && datingCheckinInWindow(at, now);
    final reason = _reason ?? (at != null && !inWindow ? 'invalid' : null);
    // R-46: a new When offers Check on me again (it replaces the last).
    final offer =
        at != null &&
        (checkin == null ||
            !checkin.isAtSameMomentAs(at.add(kDatingCheckinAfter)));
    final items = [
      loc.dating_planCheck1,
      loc.dating_planCheck2,
      loc.dating_planCheck3,
      loc.dating_planCheck4,
      loc.dating_planCheck5,
    ];
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.dating_planTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: AppContentWidth.padded(
              context,
              const EdgeInsets.all(Spacing.md),
              maxWidth: ContentWidth.form,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.check_circle_outline,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Text(
                                  item,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    loc.dating_planWhen,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                FlowSecondaryButton(
                  key: const ValueKey('dating_plan_when'),
                  label:
                      at == null
                          ? loc.dating_planPickWhen
                          : MyDateFormat.join([
                            MyDateFormat.toDate(at),
                            MyDateFormat.toTime(at),
                          ]),
                  onPressed: () => unawaited(_pickWhen()),
                ),
                const SizedBox(height: Spacing.md),
                // M-7: the heading on its own; the field labelled by its
                // question (the hint goes once a place is typed); no
                // counter until the place is near its limit.
                Semantics(
                  header: true,
                  label: loc.dating_planWhere,
                  child: ExcludeSemantics(
                    child: Text(
                      loc.dating_planWhere,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Semantics(
                  label: loc.dating_planWhere,
                  child: TextField(
                    key: const ValueKey('dating_plan_place'),
                    controller: _place,
                    maxLength: 120,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) =>
                            currentLength >= 100
                                ? Text('$currentLength/$maxLength')
                                : null,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: loc.dating_planWhereHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Builder(
                  builder:
                      (button) => FlowPrimaryButton(
                        key: const ValueKey('dating_plan_share'),
                        label: loc.dating_planShare,
                        onPressed:
                            text == null
                                ? null
                                : () => unawaited(
                                  _send(
                                    button,
                                    ref.read(datingShareProvider),
                                    text,
                                  ),
                                ),
                      ),
                ),
                const SizedBox(height: Spacing.sm),
                Builder(
                  builder:
                      (button) => FlowSecondaryButton(
                        key: const ValueKey('dating_plan_sms'),
                        label: loc.dating_planSms,
                        onPressed:
                            text == null
                                ? null
                                : () => unawaited(
                                  _send(
                                    button,
                                    ref.read(datingSmsProvider),
                                    text,
                                  ),
                                ),
                      ),
                ),
                const SizedBox(height: Spacing.md),
                if (unknown)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Spacing.sm,
                    children: [
                      DatingCalmLine(loc.dating_planCheckinUnknown),
                      FlowTextLink(
                        label: loc.dating_tryAgain,
                        onPressed: () => unawaited(_readCheckin()),
                      ),
                    ],
                  ),
                if (checkin != null || unknown) ...[
                  if (checkin != null)
                    DatingCalmLine(
                      unreachable
                          ? loc.dating_planCheckinNoPush
                          : loc.dating_planCheckinSet(
                            MyDateFormat.toDate(checkin),
                            MyDateFormat.toTime(checkin),
                          ),
                    ),
                  FlowSecondaryButton(
                    key: const ValueKey('dating_plan_cancel'),
                    label: loc.dating_planCheckinCancel,
                    busy: _cancelling,
                    onPressed:
                        !online ? null : () => unawaited(_cancelCheckin()),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                if (checkin == null || offer)
                  FlowSecondaryButton(
                    key: const ValueKey('dating_plan_check_on_me'),
                    label: loc.dating_planCheckOnMe,
                    busy: _scheduling,
                    onPressed:
                        !offer || !online || !inWindow
                            ? null
                            : () => unawaited(_checkOnMe()),
                  ),
                if (!online && (checkin != null || offer))
                  DatingCalmLine(loc.dating_planCheckOnMeOffline),
                if (reason != null) DatingCalmLine(_refusal(loc, reason)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
