// Spec 2 W5b (§3.4, §3.15 Today, §5.6, §5.8): Today. The day's state in
// the server's words (never a countdown), today's cards and the ones still
// waiting, the family question once and the quiet note once. Interested
// says "Noted."; Not for me collapses the card and offers Undo for 5 s (20 s
// with a screen reader); the answer is sent when that ends, at the next
// answer, or when the screen closes (never as another account: D8). Cards
// cross-fade in at 200 ms and collapse at 200 ms; none of it moves under
// reduce motion. Photos come from 60-second URLs into memory only, on a
// tap with data saver on. Every answer is a fixed code mapped to copy.
//
// W5 final fix: a match this person's own Interested made shows its moment
// even after another moment this visit (M-1); a photo load overtaken by a
// block writes nothing back (M-2); and Widen is a D8 sheet (M-4). Today
// keeps the bytes it loaded for its cards (at most 9 cards of 6 photos,
// memory only; the follow-up ruling on M-12): every card shows its photos
// for the whole visit. They go with Today, a block, quick exit and
// sign-out.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/settings/never_introduce_sheets.dart'
    show showDatingAccountSheet;
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/today/block_sheet.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_reasons.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.15: cards cross-fade in and collapse at 200 ms.
const kDatingCardMotion = Duration(milliseconds: 200);

/// §3.4: the undo window, and at least 20 s with a screen reader (WCAG
/// 2.2.1).
const kDatingUndo = Duration(seconds: 5);
const kDatingUndoScreenReader = Duration(seconds: 20);

class DatingTodayScreen extends ConsumerStatefulWidget {
  const DatingTodayScreen({super.key});

  @override
  ConsumerState<DatingTodayScreen> createState() => _DatingTodayScreenState();
}

class _DatingTodayScreenState extends ConsumerState<DatingTodayScreen> {
  final _keys = DatingActionKeys();
  late final DatingTodayGateway _gateway;
  String? _account;

  /// Cards answered Interested here (the "Noted." line).
  final _noted = <String>{};

  /// Cards collapsed by Not for me (held or sent).
  final _hidden = <String>{};

  /// The Not for me held for its undo window (card id).
  String? _pending;
  Timer? _undo;
  final _answers = <String, DatingActAnswer>{};

  final _photos = <String, List<Uint8List>>{};
  final _loading = <String>{};
  final _tapped = <String>{};
  bool _family = false;
  bool _quiet = false;
  bool _momentOpened = false;

  /// W5 final fix (M-1): every moment a read this visit listed, and, once
  /// this person's own Interested made a match, the read it was answered
  /// on and the person's name: the next read's new moment is that match's.
  final _momentsKnown = <String>{};
  DatingToday? _ownMatchOn;
  String _ownMatchName = '';

  /// Spec 2 W6a (carry 7): the match act said its answer made.
  String? _ownMatchId;

  /// Spec 2 W6a fix round 1 (M-3): the moment is out. Say hello puts the
  /// chat in its place, so its push never completes: Today reads again
  /// once it is the page on top again (or when the push completes).
  bool _momentOut = false;
  bool _momentCovered = false;

  void _momentBack() {
    if (!_momentOut) return;
    _momentOut = false;
    _momentCovered = false;
    _reread();
  }

  /// Task 7b: cards blocked here (collapsed to a calm line, by first name)
  /// and blocks whose answer is still open (each sent once).
  final _blocked = <String, String>{};
  final _blocking = <String>{};

  /// The Today read the photos were last asked under (Task 7 ruling).
  DatingToday? _photoDay;

  /// T7 fix 1 (I-1): the "Not for me. Undo" bar, while it is up. It goes
  /// when the pass is sent, when the account changes and when Today
  /// closes (a screen reader keeps a bar with an action up until it is
  /// dismissed), so it never rides onto another screen or quick exit's
  /// decoy. T7 fix 2 (N-1): it is shown in Today's own messenger.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ScaffoldMessengerState? _messenger;
  bool _barUp = false;

  /// T7 fix 1 (M-9): an Interested on its way (a double tap sends one).
  final _sending = <String>{};

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(datingTodayGatewayProvider);
    _account = ref.read(datingAccountProvider);
    // D8: another account sees nothing of this one's day, and this one's
    // held answer is never sent as the next person.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _undo?.cancel();
      _closeBar();
      setState(() {
        _account = next;
        _pending = null;
        _noted.clear();
        _hidden.clear();
        _blocked.clear();
        _blocking.clear();
        _answers.clear();
        _photos.clear();
        _loading.clear();
        _tapped.clear();
        _sending.clear();
        _family = false;
        _quiet = false;
        _momentOpened = false;
        _momentsKnown.clear();
        _ownMatchOn = null;
        _ownMatchName = '';
        _ownMatchId = null;
      });
    });
  }

  @override
  void dispose() {
    _undo?.cancel();
    // §3.4: closing the screen ends the undo window.
    final id = _pending;
    // (An account change already dropped it: never sent as the next one.)
    if (id != null) {
      unawaited(_gateway.act(_keys.keyFor('pass:$id', _account), id, 'passed'));
    }
    _pending = null;
    // T7 fix 1 (I-1): the bar never outlives Today.
    // T7 fix 2 (N-1): the bar lives in Today's own ScaffoldMessenger, so
    // it leaves with Today's page, with no slide over the next screen or
    // quick exit's decoy. (The app's messenger can't take it down here:
    // the tree is locked while a page is disposed.)
    _barUp = false;
    super.dispose();
  }

  /// T7 fix 1 (I-1): takes this screen's Undo bar down (the queue too, so
  /// a bar waiting behind a closing one never shows).
  void _closeBar() {
    final messenger = _messenger;
    if (!_barUp || messenger == null || !messenger.mounted) return;
    _barUp = false;
    // T7 fix 2 (N-1): gone at once, no slide (the queue first).
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar();
  }

  /// T7 fix 1 (I-2): every page Today opens may change the day (Resume,
  /// Pause, Widen's editors), so Today reads again on the way back, as it
  /// does after the moment.
  void _reread() {
    if (mounted) ref.invalidate(datingTodayProvider(_account));
  }

  void _open(String location) =>
      unawaited(context.push(location).whenComplete(_reread));

  bool get _reduce => MediaQuery.of(context).disableAnimations;

  /// Sends the held Not for me now (the window ended, or another answer).
  Future<void> _flush() async {
    final id = _pending;
    if (id == null) return;
    _undo?.cancel();
    _pending = null;
    _closeBar();
    final account = _account;
    final r = await _gateway.act(
      _keys.keyFor('pass:$id', account),
      id,
      'passed',
    );
    _keys.settle('pass:$id', reason: r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      if (!r.ok && r.reason != 'introduction_unavailable') {
        _hidden.remove(id);
        _answers[id] = r;
      }
    });
  }

  Future<void> _interested(DatingIntroCard c) async {
    // T7 fix 1 (M-9): one answer per card, however fast the second tap
    // comes (on its way, or already Noted before the rebuild).
    if (_hidden.contains(c.id) ||
        _noted.contains(c.id) ||
        !_sending.add(c.id)) {
      return;
    }
    final account = _account;
    try {
      await _flush();
      // T7 fix 1 (M-4): never this card under another account.
      if (!mounted || _account != account) return;
      // M-1: the read this answer is given on.
      final on = ref.read(datingTodayProvider(account)).valueOrNull;
      final r = await _gateway.act(
        _keys.keyFor('int:${c.id}', account),
        c.id,
        'interested',
      );
      _keys.settle('int:${c.id}', reason: r.reason);
      if (!mounted || _account != account) return;
      setState(() {
        _answers[c.id] = r;
        if (r.ok) _noted.add(c.id);
      });
      if (r.matched) {
        // M-1: the card leaves Today; its moment opens on the next read.
        _ownMatchOn = on ?? DatingToday.failed;
        _ownMatchName = c.card.displayName?.trim() ?? '';
        _ownMatchId = r.matchId;
        ref.invalidate(datingTodayProvider(account));
      }
    } finally {
      _sending.remove(c.id);
    }
  }

  Future<void> _notForMe(DatingIntroCard c) async {
    // T7 fix 1: a card already folding away takes no second answer.
    if (_hidden.contains(c.id) || _sending.contains(c.id)) return;
    final account = _account;
    await _flush();
    // T7 fix 1 (M-4): never this card under another account.
    if (!mounted || _account != account) return;
    final loc = AppLocalizations.of(context)!;
    final window =
        MediaQuery.of(context).accessibleNavigation
            ? kDatingUndoScreenReader
            : kDatingUndo;
    setState(() {
      _hidden.add(c.id);
      _pending = c.id;
      _answers.remove(c.id);
    });
    // T7 fix 1 (M-3): one window at a time.
    _undo?.cancel();
    _undo = Timer(window, _flush);
    final messenger = _messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    _barUp = true;
    final bar = messenger.showSnackBar(
      SnackBar(
        duration: window,
        content: Text(loc.dating_cardNotForMeDone),
        action: SnackBarAction(
          label: loc.dating_undo,
          onPressed: () {
            // T7 fix 1 (I-1): never on a closed screen or a sent pass.
            if (!mounted || _pending != c.id) return;
            _undo?.cancel();
            setState(() {
              _pending = null;
              _hidden.remove(c.id);
            });
          },
        ),
      ),
    );
    unawaited(
      bar.closed.then((_) {
        if (_pending == null || _pending == c.id) _barUp = false;
      }),
    );
  }

  /// Task 7b (§3.4 More, §3.6 Block; D8): the overflow, the confirm, then
  /// one request under one key, as the account that opened them; the held
  /// Not for me goes first (the next action). Blocked, the card collapses
  /// to a calm line; a refusal is the card's own answer line.
  Future<void> _more(DatingIntroCard c) async {
    if (_blocking.contains(c.id)) return;
    final account = _account;
    final name = c.card.displayName?.trim() ?? '';
    final more = await showDatingCardMoreSheet(
      context,
      account: account,
      name: name,
    );
    if (!more || !mounted || _account != account) return;
    final block = await showDatingBlockSheet(
      context,
      account: account,
      name: name,
    );
    if (!block || !mounted || _account != account) return;
    // T7b fix 1 (M-3): the card's answers wait while its block is out.
    setState(() => _blocking.add(c.id));
    await _flush();
    if (!mounted || _account != account) return;
    setState(() => _answers.remove(c.id));
    final r = await _gateway.block(
      _keys.keyFor('block:${c.id}', account),
      c.id,
    );
    _keys.settle('block:${c.id}', reason: r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      _blocking.remove(c.id);
      if (r.ok) {
        _blocked[c.id] = name;
        // T7b fix 1 (M-2): the person's photos leave the device's memory
        // (W5 final fix M-2: a load still out for them writes nothing).
        _photos.remove(c.id);
        DatingPhotoMemory.forget('introduction', c.id);
      } else {
        _answers[c.id] = DatingActAnswer(ok: false, reason: r.reason);
      }
    });
  }

  void _loadPhotos(DatingIntroCard c) {
    if (_photos.containsKey(c.id) || !_loading.add(c.id)) return;
    final account = _account;
    // Task 7 ruling (Task 6 carry): one slot per card position, so a photo
    // that fails to sign leaves its own slot empty (its caption stays put).
    // A photo failure never reads Today again: the slots stay calm until a
    // fresh Today read (see build).
    loadDatingPhotos(
      _gateway,
      ref.read(datingPhotoFetchProvider),
      'introduction',
      c.id,
      positions: c.photoPositions,
    ).then((bytes) {
      if (!mounted || _account != account) return;
      // W5 final fix (M-2): blocked while it loaded: nothing comes back.
      if (_blocked.containsKey(c.id)) return;
      setState(() {
        _loading.remove(c.id);
        _photos[c.id] = bytes;
      });
    });
  }

  Future<void> _answerFamily(String? value) async {
    final account = _account;
    setState(() => _family = true);
    final w =
        value == null
            ? await _gateway.dismissNote('family')
            : await _gateway.saveFamily(
              _keys.keyFor('family', '$account|$value'),
              value,
            );
    _keys.settle('family', reason: w.reason);
  }

  void _openMoment(DatingToday day) {
    // W5 final fix (M-1): "one moment per visit" is for moments that were
    // waiting or came from the other side; the match this person's own
    // Interested just made shows its moment (its card has left Today).
    DatingMoment? own;
    final on = _ownMatchOn;
    if (on != null && !identical(day, on)) {
      _ownMatchOn = null;
      final arrived = [
        for (final m in day.moments)
          if (!_momentsKnown.contains(m.matchId)) m,
      ];
      // Spec 2 W6a (carry 7): the exact match, when act named it.
      own =
          day.moments.where((m) => m.matchId == _ownMatchId).firstOrNull ??
          arrived.where((m) => m.name.trim() == _ownMatchName).lastOrNull ??
          arrived.lastOrNull;
      _ownMatchId = null;
    }
    _momentsKnown.addAll([for (final m in day.moments) m.matchId]);
    if (own == null && (_momentOpened || day.moments.isEmpty)) return;
    _momentOpened = true;
    final m = own ?? day.moments.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // T7 fix 1 (M-1): the account rides with the moment.
      _momentOut = true;
      context
          .push(DatingPaths.match(m.matchId), extra: (m, day.myName, _account))
          .whenComplete(_momentBack);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    // T7 fix 2 (N-1): in the frame Today stops being the page on top (left,
    // quick exit, the lock, a page over it), its Undo bar goes, with no
    // slide (it is in Today's own messenger, a descendant, so it may be
    // taken down during this build), and the held pass is sent once the
    // frame ends (or by dispose, whichever comes first).
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_momentOut) {
      if (!current) {
        _momentCovered = true;
      } else if (_momentCovered) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _momentBack());
      }
    }
    if (!current && _barUp) {
      _closeBar();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_flush());
      });
    }
    final read = ref.watch(datingTodayProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final day = read.valueOrNull;
    // Task 7 ruling: a fresh ok Today read (it gives the photos fresh
    // tries) lets a card with an empty slot ask again; nothing else does.
    if (day != null && day.ok && !identical(day, _photoDay)) {
      _photoDay = day;
      _photos.removeWhere((_, b) => b.any((x) => x.isEmpty));
    }
    if (day != null && day.ok) _openMoment(day);
    return AllowLargeText(
      // T7 fix 2 (N-1): Today's own messenger (its Undo bar is Today's).
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: AppBar(
            // Spec 2 W6a fix round 1 (I-3): the only page goes back to Me.
            leading: datingRootBackButton(context),
            title: Text(loc.dating_todayTitle),
          ),
          body: SafeArea(
            child: switch (read) {
              AsyncData(value: final d) when d.ok => _day(
                context,
                loc,
                d,
                online,
              ),
              AsyncData(value: final d) => ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [_refusal(loc, d.reason, online)],
              ),
              AsyncError() => ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [_refusal(loc, 'failed', online)],
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }

  Widget _refusal(AppLocalizations loc, String? reason, bool online) {
    final retry = FlowSecondaryButton(
      label: loc.dating_tryAgain,
      onPressed: () => ref.invalidate(datingTodayProvider(_account)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (reason) {
        _ when !online => [DatingCalmLine(loc.dating_offline), retry],
        'reverify_device' => [const DatingReverifyLine()],
        'not_eligible' => [DatingCalmLine(loc.dating_sectionUnavailable)],
        'busy' => [DatingCalmLine(loc.dating_busy), retry],
        // Task 7 ruling (Task 4 M-8): a paused person reads the home's
        // paused line, calm, with no retry; Resume is in Dating settings.
        'paused' => [
          DatingCalmLine(loc.dating_sectionPaused),
          FlowTextLink(
            label: loc.dating_settingsTitle,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _open(DatingPaths.settings),
          ),
        ],
        _ => [
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          retry,
        ],
      },
    );
  }

  String? _region(AppLocalizations loc, DatingToday d) =>
      d.regionNameKey == null ? null : datingListName(loc, d.regionNameKey!);

  Widget _day(
    BuildContext context,
    AppLocalizations loc,
    DatingToday d,
    bool online,
  ) {
    final theme = Theme.of(context);
    final region = _region(loc, d);
    final at = d.dropAt?.toLocal();
    final line = switch (d.state) {
      DatingTodayState.delivered => null,
      DatingTodayState.beforeDrop when at != null => loc.dating_todayBeforeDrop(
        MyDateFormat.toTime(at),
      ),
      DatingTodayState.coolOff when at != null => loc.dating_sectionFirstDrop(
        MyDateFormat.toDate(at),
        MyDateFormat.toTime(at),
      ),
      // T7 fix 1 (M-7): every day state says something.
      DatingTodayState.beforeDrop ||
      DatingTodayState.coolOff => loc.dating_todayLaterNoTime,
      DatingTodayState.queueFull => loc.dating_todayQueueFull,
      DatingTodayState.pausedOpenChats => loc.dating_todayPausedChats,
      DatingTodayState.empty =>
        region == null
            ? loc.dating_todayEmptyNoRegion
            : loc.dating_todayEmpty(region),
      _ => null,
    };
    // T7 fix 1 (M-7): a day with nothing on it, in a state this app can't
    // name (or delivered empty), still says so.
    final shown =
        line ??
        (d.cards.isEmpty && d.waiting.isEmpty
            ? loc.dating_todayNothingNew
            : null);
    final widen = FlowSecondaryButton(
      label: loc.dating_todayWiden,
      onPressed:
          online
              ? () => showDatingWidenSheet(
                context,
                d,
                account: _account,
                onReturn: _reread,
              )
              : null,
    );
    // Every card is built (at most nine): each is in the tree to scroll to.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) DatingCalmLine(loc.dating_offline),
          if (shown != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Text(shown, style: theme.textTheme.bodyLarge),
            ),
          if (d.state == DatingTodayState.empty && !(d.quietNote && !_quiet))
            widen,
          if (d.quietNote && !_quiet) _quietNote(loc, region, online, d),
          if (d.familyQuestion && !_family) _familyQuestion(loc, online),
          for (final c in d.cards) _tile(loc, c, d, online),
          if (d.waiting.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              child: Semantics(
                header: true,
                child: Text(
                  loc.dating_todayWaiting,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            for (final c in d.waiting) _tile(loc, c, d, online),
          ],
        ],
      ),
    );
  }

  Widget _quietNote(
    AppLocalizations loc,
    String? region,
    bool online,
    DatingToday d,
  ) => Card(
    margin: const EdgeInsets.only(bottom: Spacing.md),
    child: Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // T7 fix 1 (M-6): never a country phrase as a region's name.
          Text(
            region == null
                ? loc.dating_quietNoteNoRegion
                : loc.dating_quietNote(region),
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.dating_todayWiden,
            onPressed:
                online
                    ? () {
                      setState(() => _quiet = true);
                      unawaited(_gateway.dismissNote('quiet'));
                      showDatingWidenSheet(
                        context,
                        d,
                        account: _account,
                        onReturn: _reread,
                      );
                    }
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          // T7 fix 1 (M-6): it opens Dating settings (Pause is there), so it
          // says so; (I-2) Today reads again on the way back.
          FlowSecondaryButton(
            label: loc.dating_settingsTitle,
            onPressed: () {
              setState(() => _quiet = true);
              unawaited(_gateway.dismissNote('quiet'));
              _open(DatingPaths.settings);
            },
          ),
        ],
      ),
    ),
  );

  Widget _familyQuestion(AppLocalizations loc, bool online) => Card(
    margin: const EdgeInsets.only(bottom: Spacing.md),
    child: Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_familyQuestion),
          for (final (value, label) in [
            ('early', loc.dating_familyEarly),
            ('when_serious', loc.dating_familyWhenSerious),
            ('our_decision', loc.dating_familyOwn),
          ]) ...[
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: label,
              onPressed: online ? () => _answerFamily(value) : null,
            ),
          ],
          const SizedBox(height: Spacing.sm),
          FlowTextLink(
            label: loc.dating_familySkip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _answerFamily(null),
          ),
        ],
      ),
    ),
  );

  Widget _tile(
    AppLocalizations loc,
    DatingIntroCard c,
    DatingToday d,
    bool online,
  ) {
    // Task 7b: blocked here, the card is a calm line naming the person.
    final blocked = _blocked[c.id];
    final hidePhotos = d.dataSaver && !_tapped.contains(c.id);
    if (blocked == null &&
        !hidePhotos &&
        c.card.photoIds.isNotEmpty &&
        !c.card.photosAfterMutual) {
      _loadPhotos(c);
    }
    final tile = DatingCardView(
      card: c.card,
      photos: _photos[c.id] ?? const [],
      photosHidden: hidePhotos,
      onShowPhotos: () => setState(() => _tapped.add(c.id)),
      trailing:
          (part) => switch (part) {
            'intention' => _reasons(loc, c),
            'photos' => _actions(loc, c, online),
            _ => null,
          },
    );
    final shown = Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child:
          blocked == null
              ? tile
              // T7b fix 1 (M-1): never "You've blocked ."
              : DatingCalmLine(
                blocked.isEmpty
                    ? loc.dating_blockDoneNoName
                    : loc.dating_blockDone(blocked),
              ),
    );
    // Reduce motion: the card simply goes (and comes back); no animated
    // wrapper at all (an AnimatedSize at zero duration re-dirties itself
    // mid-layout).
    if (_reduce) {
      return KeyedSubtree(
        key: ValueKey('dating_today_card_${c.id}'),
        child:
            _hidden.contains(c.id)
                ? const SizedBox(width: double.infinity)
                : shown,
      );
    }
    const motion = kDatingCardMotion;
    // §3.4, §3.15: Not for me fades the card out while it collapses (both
    // 200 ms; T7 fix 1, M-5); Undo brings it back the same way. Nothing
    // moves under reduce motion. The fading card is laid over the space
    // as it shrinks, so the two run together; AnimatedSize clips only
    // while it moves (the card's shadow is never cut at rest).
    return AnimatedSize(
      key: ValueKey('dating_today_card_${c.id}'),
      duration: motion,
      alignment: AlignmentDirectional.topCenter,
      child: AnimatedSwitcher(
        duration: motion,
        layoutBuilder:
            (current, previous) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in previous)
                  PositionedDirectional(top: 0, start: 0, end: 0, child: p),
                if (current != null) current,
              ],
            ),
        child:
            _hidden.contains(c.id)
                ? const SizedBox(
                  key: ValueKey('hidden'),
                  width: double.infinity,
                )
                : TweenAnimationBuilder<double>(
                  key: ValueKey(blocked == null ? 'shown' : 'blocked'),
                  tween: Tween(begin: 0, end: 1),
                  duration: motion,
                  builder:
                      (context, v, child) => Opacity(opacity: v, child: child),
                  child: shown,
                ),
      ),
    );
  }

  /// The card's answers (§3.4), after its photos. Task 7 ruling: one
  /// column of its own, so Task 7b's More overflow (Block; Report in W7a)
  /// joins it after Not for me without moving anything else.
  Widget _actions(AppLocalizations loc, DatingIntroCard c, bool online) {
    final answer = _answers[c.id];
    final noted = _noted.contains(c.id) || c.acted == 'interested';
    final name = c.card.displayName?.trim() ?? '';
    // T7b fix 1 (M-3): no answer while this card's block is out.
    final open = online && !_blocking.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (noted)
            // T7 fix 1 (M-8): never "If  is interested".
            DatingCalmLine(
              name.isEmpty
                  ? loc.dating_cardNotedNoName
                  : loc.dating_cardNoted(name),
            )
          else ...[
            FlowPrimaryButton(
              label: loc.dating_cardInterested,
              onPressed: open ? () => _interested(c) : null,
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_cardNotForMe,
              onPressed: open ? () => _notForMe(c) : null,
            ),
          ],
          if (answer != null && !answer.ok) _answerLine(loc, answer),
          // Task 7b (§3.4): the overflow after the answers (W7a adds
          // Report), read as "More for {name}".
          const SizedBox(height: Spacing.sm),
          // (Its own node: else it merges into the card's text.)
          Semantics(
            container: true,
            label:
                name.isEmpty
                    ? loc.dating_cardMoreNoName
                    : loc.dating_cardMoreLabel(name),
            button: true,
            excludeSemantics: true,
            onTap: () => _more(c),
            child: FlowTextLink(
              label: loc.dating_cardMore,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => _more(c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reasons(AppLocalizations loc, DatingIntroCard c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_cardWhyTitle, style: theme.textTheme.titleSmall),
          for (final line in datingReasonLines(loc, c))
            Text(line, style: theme.textTheme.bodyMedium),
          Text(loc.dating_cardChemistry, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _answerLine(AppLocalizations loc, DatingActAnswer a) => switch (a
      .reason) {
    'reverify_device' => const DatingReverifyLine(),
    'introduction_unavailable' => DatingCalmLine(loc.dating_cardGone),
    'busy' => DatingCalmLine(loc.dating_busy),
    'rate_limited' => FlowErrorLine(
      text: loc.dating_errorRateLimited,
      liveRegion: true,
    ),
    'not_eligible' => DatingCalmLine(loc.dating_sectionUnavailable),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };
}

/// §3.4 "Widen who I meet": each row opens its editor; nothing changes by
/// itself. W5c adds Other countries.
///
/// T7 fix 1 (I-2): [onReturn] runs when the editor a row opened closes
/// (Today reads again, so Widen shows what was saved).
///
/// W5 final fix (M-4, D8): opened as [account] (the one [d] was read for);
/// once another account signs in the sheet shows nothing of [d] (no ages,
/// no scope) and closes, opening nothing.
Future<void> showDatingWidenSheet(
  BuildContext context,
  DatingToday d, {
  required String? account,
  VoidCallback? onReturn,
}) {
  final loc = AppLocalizations.of(context)!;
  final scope = switch (d.scope) {
    'side' => loc.dating_scopeSide,
    'country' => loc.dating_widenCountry,
    _ => loc.dating_scopeRegion,
  };
  // A row closes the sheet (once), then opens its editor.
  void open(void Function(Object?) close, String location) {
    close(null);
    context.push(location).whenComplete(() => onReturn?.call());
  }


  return showDatingAccountSheet<Object>(
    context,
    name: 'widen',
    account: account,
    builder:
        (sheet, close) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.dating_todayWiden,
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (d.minAge != null && d.maxAge != null)
                  InfoRowWidget(
                    title: loc.dating_widenAges(d.minAge!, d.maxAge!),
                    subtitle: '',
                    icon: Icons.cake_outlined,
                    showAvatar: false,
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                    onTap: () => open(close, DatingPaths.stepFromToday('meet')),
                  ),
                InfoRowWidget(
                  title: loc.dating_widenHowFar(scope),
                  subtitle: '',
                  icon: Icons.near_me_outlined,
                  showAvatar: false,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  onTap: () => open(close, DatingPaths.stepFromToday('where')),
                ),
                // Spec 2 W5c (§2.6, §3.4): once the read answers.
                Consumer(
                  builder: (context, ref, _) {
                    final account = ref.watch(datingAccountProvider);
                    final o =
                        ref.watch(datingAbroadProvider(account)).valueOrNull;
                    // W5 final fix (M-11): eligible or not (the page
                    // offers the off-only path, never the list).
                    if (o == null || !o.ok) {
                      return const SizedBox.shrink();
                    }
                    return InfoRowWidget(
                      title: loc.dating_abroadTitle,
                      subtitle: '',
                      icon: Icons.public,
                      showAvatar: false,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                      // Task 7 fix 1 (I-2): Today reads again on return.
                      onTap: () => open(close, DatingPaths.abroad),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
  );
}
