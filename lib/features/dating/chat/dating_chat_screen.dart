// Spec 2 W6a (§3.6, §3.15 Chat, §6.1): the dating chat, its own screen and
// widgets (nothing from lib/features/chat or games: an architecture test
// pins it). "{Name}, {age}" and the Safety button; Swap contacts from 72
// hours, then its states; the messages as a list read with sender names,
// hidden spans "•••" read "hidden contact detail" (a tap says why); text
// only, 1-1,000 characters, no attachment of any kind; own messages show
// "Sending…", then nothing, or "Not sent. Tap to try again."; no read
// receipts, typing or presence. New messages appear without animation.
// An ended chat is read-only under "This conversation has ended." It reads
// again on a chat signal, on resume and on the way back from a sheet.
// D8: another account sees nothing of this chat, and nothing typed is
// sent as the next person. Memory only (D20): nothing typed is kept when
// the screen closes.
//
// Fix round 1: a refused background read keeps the chat (its messages,
// Not sent bubbles, composer and shield) under a line, and only a gone
// match or a first read replaces it (I-1); every message read is held by
// id, so a newer page never drops one already shown (I-2); the 1,000 limit
// is counted as the server counts (code points) and said, never a silent
// Send (M-10); the composer stays reachable at large text with the
// keyboard up (M-12); on an iPad the chat sits in the chat column (M-14).
//
// Final client fix wave (final-client-review.md): the chat reads again when
// the connection comes back (I-1; a realtime rejoin arrives as a signal);
// a masked message is one flowing text (I-2); an older page in flight when
// the newest page starts again is dropped (C-2); masked and plain bubbles
// keep one rhythm (C-3); the composer mirrors right to left (C-4); the
// senders of pending dismissals stop on another account (C-6); after an
// answer the guided card changes once, when the read lands (C-7); Answer
// carries the weight over Skip and a top card new to the open chat slides
// in (C-8, §3.15); the top cards take the safety card's surface (M-6); no
// second Block (M-7); the guided state is read only while a question is
// open (M-8); a guided answer survives the sheet's swipe (M-9).
//
// Owner follow-up (fallback poll): while the signal channel is not joined
// (some networks block WebSockets), the chat reads again on the signals'
// slow poll, only while it is the page shown and no read is on its way,
// and never for another account; the connection's return does not read
// again when a rejoin already has (N-1).
import 'dart:async';
import 'dart:math' as math;

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/chat/chat_sheets.dart';
import 'package:attune/features/dating/chat/guided_questions.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/chat/safety_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_device_check.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart'
    show DatingLinkMoment, datingLinkDone;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/today/block_sheet.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart'
    show supportDialString;
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart'
    show supportLauncherProvider;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.6: at most this many characters in a message, counted as the server
/// counts them (`char_length`: code points, so `String.runes`).
const kDatingMessageMax = 1000;

/// The counter shows from here (fix round 1, M-10).
const kDatingMessageCounterFrom = 900;

/// [text]'s length as the server counts it.
int datingMessageLength(String text) => text.runes.length;

/// Send refusals that are final for this message: never offered again.
const _finalRefusals = {'closed', 'match_unavailable', 'invalid', 'restricted'};

/// Send refusals with their own line above "Not sent. Tap to try again."
const _namedRetryable = {'rate_limited', 'unavailable'};

/// Task 9 fix round 1 (I-1): the messages never get less than this (one
/// bubble at text 2.0) while the top area has room to give.
const kDatingMessagesMin = 96.0;

/// I-1: the chat's column. The lines under the chat are laid out first
/// (at most 0.45 of the height), then the top area (at most [topShare],
/// never into [kDatingMessagesMin] of the messages), then the messages
/// take the rest.
class _ChatColumn extends MultiChildLayoutDelegate {
  _ChatColumn({required this.topShare});

  final double topShare;

  @override
  void performLayout(Size size) {
    final w = size.width;
    final lines = layoutChild(
      'lines',
      BoxConstraints(minWidth: w, maxWidth: w, maxHeight: size.height * 0.45),
    );
    var top = 0.0;
    if (hasChild('top')) {
      final room = size.height - lines.height - kDatingMessagesMin;
      top =
          layoutChild(
            'top',
            BoxConstraints(
              minWidth: w,
              maxWidth: w,
              maxHeight: math.max(0, math.min(size.height * topShare, room)),
            ),
          ).height;
      positionChild('top', Offset.zero);
    }
    layoutChild(
      'messages',
      BoxConstraints.tightFor(
        width: w,
        height: math.max(0, size.height - lines.height - top),
      ),
    );
    positionChild('messages', Offset(0, top));
    positionChild('lines', Offset(0, size.height - lines.height));
  }

  @override
  bool shouldRelayout(_ChatColumn oldDelegate) =>
      oldDelegate.topShare != topShare;
}

/// One of this person's messages on its way, or not sent.
class _Outgoing {
  _Outgoing(this.key, this.text);

  final String key;
  final String text;
  bool failed = false;
  String? reason;

  /// Sent: the id the server gave it (it goes when a read lists it).
  String? sentId;

  /// Sent: the text as the server returned it (masked like any other copy,
  /// §6.1); null while it is on its way or not sent.
  String? shown;
}

/// Spec 2 W6c (§3.6): a card at the top of the chat (a timebox card, the
/// guided question, the tip). As the safety cards (W6b fix round 1, I-1):
/// one already there when the chat opens is shown as it is; one that
/// arrives while the chat is open is read out, once, and never again (not
/// on a rebuild, not on reopening). Final client fix (C-8, §3.15 "cards
/// slide in at 150 ms"): that new one slides in, as a safety card does,
/// and not at all under reduce motion.
class _TopCard extends StatefulWidget {
  const _TopCard({
    super.key,
    required this.id,
    required this.shown,
    required this.child,
  });

  final String id;

  /// The ids of the top cards this open chat has shown.
  final Set<String> shown;
  final Widget child;

  @override
  State<_TopCard> createState() => _TopCardState();
}

class _TopCardState extends State<_TopCard>
    with SingleTickerProviderStateMixin {
  /// Whether this card arrived new (fixed for this card's life).
  late final bool _fresh;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kDatingCardSlide,
  );

  /// Made once (a CurvedAnimation listens to its parent until disposed).
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _fresh = !widget.shown.contains(widget.id);
    widget.shown.add(widget.id);
    if (!_fresh) _slide.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_fresh || MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 1;
    } else if (_slide.status == AnimationStatus.dismissed) {
      _slide.forward();
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    axisAlignment: -1,
    child: Semantics(container: true, liveRegion: _fresh, child: widget.child),
  );
}

class DatingChatScreen extends ConsumerStatefulWidget {
  const DatingChatScreen({super.key, required this.matchId, this.now});

  final String matchId;

  /// The clock (tests pin it).
  final DateTime Function()? now;

  @override
  ConsumerState<DatingChatScreen> createState() => _DatingChatScreenState();
}

class _DatingChatScreenState extends ConsumerState<DatingChatScreen>
    with WidgetsBindingObserver {
  final _keys = DatingActionKeys();
  final _composer = TextEditingController();
  late final DatingChatGateway _gateway;
  String? _account;

  /// The last page shown: the last good one, or (first read, gone match)
  /// the refusal that replaced it.
  DatingChatPage? _page;

  /// Every message read, by id (I-2: a newer page only adds or updates).
  final _held = <String, DatingChatMessage>{};
  bool _more = false;
  bool _loadingOlder = false;
  String? _olderReason;

  /// C-2: each older load's ticket; a restart or another account moves it,
  /// and a page that lands after that is dropped.
  int _olderTicket = 0;
  final _outgoing = <_Outgoing>[];
  String? _blockedName;

  /// Spec 2 W9 fix round 1 (M-1): Take it back is being sent.
  bool _takingBack = false;

  /// Spec 2 W9 final client fix (M-3): the moment is being answered.
  bool _linkLeaving = false;
  bool _offlineTried = false;
  String? _actionReason;

  /// too_early: when Swap opens, as the server said.
  DateTime? _actionFrom;

  /// I-1: a background read refused while the chat is shown.
  String? _readReason;
  int _reads = 0;

  /// Fallback poll: reads on their way (a poll never overlaps one), and
  /// the chat's route (a poll reads only while it is on top).
  int _inFlight = 0;
  ModalRoute<Object?>? _route;

  /// Spec 2 W6b (§3.6): this person's safety cards by id, each shown under
  /// its message. A read only adds to them (a failed or empty read never
  /// hides one); Dismiss takes one away here for good.
  final _cards = <String, DatingSafetyCard>{};
  final _dismissedCards = <String>{};

  /// Fix round 1 (I-1): the first cards read since the chat opened (what
  /// it finds was there before: shown as it is), and the cards already
  /// shown (each card adds itself when first built: never sliding or read
  /// out again, even when scrolled back into view).
  bool _cardsBaselined = false;
  final _shownCards = <String>{};

  /// M-1: dismissals are being sent (one sender at a time), for this
  /// account (C-6: another account's sender never waits on it).
  String? _dismissingFor;

  /// Spec 2 W6c (§3.6): the guided conversation as this side sees it (a
  /// failed read keeps the last one), and the timebox card this visit has
  /// answered.
  DatingGuided _guided = DatingGuided.none;
  String? _timeboxDone;
  int _guidedReads = 0;

  /// A skip or an answer is on its way (a second tap does nothing).
  bool _guidedBusy = false;

  /// C-7: the question this side has just answered; the card waits (its
  /// buttons off) until the guided read that follows lands.
  String? _guidedAnswered;

  /// An answer not sent (refused or offline), by question: offered again
  /// in the sheet. Memory only (D20).
  final _guidedDrafts = <String, String>{};

  /// The top cards this open chat has shown; the first reads find what was
  /// already there (shown as it is, never read out).
  final _shownTop = <String>{};
  bool _guidedBaselined = false;
  bool _pageBaselined = false;

  /// Close kindly's sheet or call is on its way.
  bool _closing = false;

  /// Fix round 1 (I-1): the top area's scroll (its scrollbar shows there
  /// is more), and (M-3) timebox dismissals are being sent.
  final _topScroll = ScrollController();

  /// I-1: the top area has more than it shows (its scrollbar shows).
  bool _topOverflows = false;

  /// C-6: the account whose timebox dismissals are being sent.
  String? _sendingTimeboxesFor;

  DateTime get _now => (widget.now ?? DateTime.now)();

  bool get _online => ref.read(datingOnlineProvider).valueOrNull ?? true;

  /// Fallback poll: the chat is the page shown and no read is on its way.
  bool get _pollDue =>
      mounted && _inFlight == 0 && (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway = ref.read(datingChatGatewayProvider);
    _account = ref.read(datingAccountProvider);
    // D8: another account starts from nothing; nothing typed is sent as it.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _account = next;
        _page = null;
        _held.clear();
        _more = false;
        _loadingOlder = false;
        _olderReason = null;
        _olderTicket++;
        _outgoing.clear();
        _blockedName = null;
        _cards.clear();
        _dismissedCards.clear();
        _cardsBaselined = false;
        _shownCards.clear();
        _guided = DatingGuided.none;
        _timeboxDone = null;
        _guidedBusy = false;
        _guidedAnswered = null;
        _guidedKnown = false;
        _guidedDrafts.clear();
        _shownTop.clear();
        _guidedBaselined = false;
        _pageBaselined = false;
        _closing = false;
        _offlineTried = false;
        _actionReason = null;
        _actionFrom = null;
        _readReason = null;
        _composer.clear();
        _takingBack = false;
        _linkLeaving = false;
      });
      unawaited(_read());
    });
    // Spec 2 W8 final client fix (I-1): a device check whose answer changed
    // what the phone knew (a trip began or ended) reads the chat again.
    ref.listenManual<int>(
      datingDeviceCheckerProvider.select((s) => s.changes),
      (previous, next) {
        if (previous != next && mounted) unawaited(_read());
      },
    );
    // Final client fix (I-1): realtime never replays what changed while the
    // connection was down, so its return reads again (as the kit does).
    ref.listenManual<AsyncValue<bool>>(datingOnlineProvider, (previous, next) {
      // N-1: a rejoin since the phone went offline has already read again.
      if (ref.read(datingChatSignalsProvider(_account)).rejoined) return;
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        unawaited(_read());
      }
    });
    unawaited(_read());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    _topScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read(resumed: true));
  }

  /// The newest page, read again (a signal, resume, a sheet closing).
  Future<void> _read({bool resumed = false}) async {
    final account = _account;
    final n = ++_reads;
    if (account == null) return;
    // Fix round 1 (M-3): every read here pushes the next poll a full wait
    // out (the signals exist once the chat has built).
    if (ref.exists(datingChatSignalsProvider(account))) {
      ref.read(datingChatSignalsProvider(account).notifier).readStarted();
    }
    // The cards never hold the messages up (fail-open: none on a failure).
    unawaited(_readCards(account));
    // M-8: once the questions are done (a good read with none open) they
    // stay done (answers and skips only add up), so the state is read
    // only while one is open or not yet known.
    if (_guidedDue) unawaited(_readGuided(account));
    // Spec 2 W8 final client fix (I-1): after a device check under way (at
    // most 3 s; on resume one is started when due), so a trip that began is
    // hidden from this read. With none, the read goes in this same turn.
    final checker = ref.read(datingDeviceCheckerProvider.notifier);
    final check = resumed ? checker.ensure(account) : checker.running(account);
    final page = await _counted(() async {
      if (check != null) await DatingDeviceChecker.wait(check);
      return _gateway.messages(widget.matchId);
    });
    if (!mounted || _account != account || n != _reads) return;
    setState(() {
      if (page.ok) {
        _merge(page);
        _page = page;
        // Spec 2 W6c: the first page's timebox card was there before.
        if (!_pageBaselined) {
          _pageBaselined = true;
          final timebox = page.header?.timebox;
          if (timebox != null) _shownTop.add('timebox:$timebox');
        }
        _readReason = null;
        // A message sent and now listed is no longer on its way.
        _outgoing.removeWhere((o) => _held.containsKey(o.sentId));
      } else if (_page?.ok != true || page.reason == 'match_unavailable') {
        // A first read, or the match is gone: the refusal is the page.
        _page = page;
        _held.clear();
        _cards.clear();
        _more = false;
        _readReason = null;
      } else {
        // I-1: the chat stays; the line says why.
        _readReason = page.reason;
      }
    });
    // M-1: a good read sends again the dismissals not yet confirmed.
    if (page.ok && _online) unawaited(_sendDismissals(account));
    if (page.ok && _online) unawaited(_sendTimeboxes(account));
  }

  /// Fallback poll: a read the poll never overlaps (fix round 1, M-4: the
  /// cards' and the guided state's reads too, so a poll waits for them).
  Future<T> _counted<T>(Future<T> Function() read) async {
    _inFlight++;
    try {
      return await read();
    } finally {
      _inFlight--;
    }
  }

  /// M-1: [account]'s dismissals the server has not confirmed (memory).
  Set<String> _pendingDismissals(String account) =>
      ref.read(datingPendingCardDismissalsProvider(account));

  /// §3.6: the cards read join what is held (none on a failure; never one
  /// dismissed here or waiting to be). The first read since the chat
  /// opened finds what was already there: shown as it is (I-1).
  Future<void> _readCards(String account) async {
    final cards = await _counted(() => _gateway.cards(widget.matchId));
    if (!mounted || _account != account) return;
    final first = !_cardsBaselined;
    _cardsBaselined = true;
    final pending = _pendingDismissals(account);
    final added = [
      for (final c in cards)
        if (!_dismissedCards.contains(c.id) &&
            !pending.contains(c.id) &&
            !_cards.containsKey(c.id))
          c,
    ];
    if (added.isEmpty) return;
    setState(() {
      for (final c in added) {
        if (first) _shownCards.add(c.id);
        _cards[c.id] = c;
      }
    });
  }

  /// M-8: whether the guided state can still change (no good read yet, a
  /// question open, or an answer waiting on its read).
  bool get _guidedDue =>
      !_guidedKnown || _guided.questionId != null || _guidedAnswered != null;

  /// M-8: a good guided read has landed for this account.
  bool _guidedKnown = false;

  /// Spec 2 W6c (§3.6): the guided state, read beside the page (it never
  /// holds the chat up). A failed read keeps the last state; the first read
  /// since the chat opened finds what was there (shown as it is). C-7: the
  /// read after this side's answer frees the card; failed, the card shows
  /// the answer as given (the waiting line).
  Future<void> _readGuided(String account) async {
    final n = ++_guidedReads;
    final guided = await _counted(() => _gateway.guided(widget.matchId));
    if (!mounted || _account != account || n != _guidedReads) return;
    final first = !_guidedBaselined;
    _guidedBaselined = true;
    final answered = _guidedAnswered;
    if (!guided.ok) {
      if (answered == null) return;
      setState(() {
        _guidedAnswered = null;
        _guidedBusy = false;
        _guided = DatingGuided(
          questionId: answered,
          answered: true,
          revealed: _guided.revealed,
        );
      });
      return;
    }
    setState(() {
      _guidedKnown = true;
      _guided = guided;
      if (answered != null) {
        _guidedAnswered = null;
        _guidedBusy = false;
      }
      if (first) _shownTop.addAll(_guidedIds(guided));
    });
  }

  /// The top-card ids [guided] shows (a new id is a new card).
  static List<String> _guidedIds(DatingGuided guided) => [
    if (guided.questionId != null)
      'guided:${guided.questionId}:${guided.answered}',
    if (guided.revealed == 1) 'tip',
  ];

  /// M-1: sends each dismissal not yet confirmed, once per pass; a
  /// confirmed one is forgotten, a refused one waits for the next read.
  /// C-6: it stops once the account changes or the chat closes (the
  /// remaining ids wait, kept for [account]); the one on its way was sent
  /// as [account], so its answer is [account]'s.
  Future<void> _sendDismissals(String account) async {
    if (_dismissingFor == account) return;
    _dismissingFor = account;
    final pending = _pendingDismissals(account);
    final tried = <String>{};
    try {
      while (true) {
        if (!mounted || _account != account) break;
        final next = pending.where((id) => !tried.contains(id)).firstOrNull;
        if (next == null) break;
        tried.add(next);
        if (await _gateway.dismissCard(next)) pending.remove(next);
      }
    } finally {
      if (_dismissingFor == account) _dismissingFor = null;
    }
  }

  /// I-2: the newest page joins what is held. With no message in common
  /// (more arrived than a page holds), it starts again from that page, so
  /// no gap is ever shown; earlier messages load from there.
  void _merge(DatingChatPage page) {
    final overlap =
        _held.isEmpty ||
        !page.more ||
        page.messages.any((m) => _held.containsKey(m.id));
    if (!overlap) {
      _held.clear();
      _olderReason = null;
      // C-2: an older page on its way belongs to what was cleared.
      _olderTicket++;
      _loadingOlder = false;
    }
    final first = _held.isEmpty;
    for (final m in page.messages) {
      _held[m.id] = m;
    }
    if (first) _more = page.more;
  }

  Future<void> _loadOlder() async {
    final account = _account;
    final all = _messages;
    if (_loadingOlder || all.isEmpty) return;
    final ticket = ++_olderTicket;
    setState(() {
      _loadingOlder = true;
      _olderReason = null;
    });
    final page = await _gateway.messages(widget.matchId, before: all.last.at);
    if (!mounted || _account != account) return;
    // C-2: the newest page started again meanwhile: this page would leave
    // a gap (its progress was reset there).
    if (ticket != _olderTicket) return;
    setState(() {
      _loadingOlder = false;
      if (page.ok) {
        for (final m in page.messages) {
          _held[m.id] = m;
        }
        _more = page.more;
      } else {
        _olderReason = page.reason;
      }
    });
  }

  /// Every message, newest first, each once.
  List<DatingChatMessage> get _messages {
    final page = _page;
    if (page == null || !page.ok) return const [];
    return _held.values.toList()..sort((a, b) {
      final at = b.at.compareTo(a.at);
      return at != 0 ? at : b.id.compareTo(a.id);
    });
  }

  Future<void> _send(_Outgoing? retry) async {
    final online = ref.read(datingOnlineProvider).valueOrNull ?? true;
    final text = retry?.text ?? _composer.text;
    if (text.trim().isEmpty || datingMessageLength(text) > kDatingMessageMax) {
      return;
    }
    if (!online) {
      // §3.6: nothing is queued; what was typed stays.
      setState(() => _offlineTried = true);
      return;
    }
    final account = _account;
    final out =
        retry ?? _Outgoing(_keys.keyFor('send', [widget.matchId, text]), text);
    setState(() {
      _offlineTried = false;
      out.failed = false;
      out.reason = null;
      if (retry == null) {
        _outgoing.add(out);
        _composer.clear();
      }
    });
    final r = await _gateway.send(out.key, widget.matchId, out.text);
    // `unavailable` (messages paused; the server kept nothing) is settled as
    // busy: the same words again are the same request.
    _keys.settle('send', reason: r.reason == 'unavailable' ? 'busy' : r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      if (r.ok) {
        out.sentId = r.message?.id;
        out.shown = r.message?.text;
        // M-4: a message sent clears the last line.
        _actionReason = null;
        _actionFrom = null;
      } else {
        out.failed = true;
        out.reason = r.reason;
        // W4b carry 9: every reverify_device answer shows the re-check line.
        if (r.reason == 'reverify_device') _actionReason = r.reason;
      }
    });
    // ok, closed and a gone match read again (unavailable never shows it
    // ended).
    if (r.ok || r.reason == 'closed' || r.reason == 'match_unavailable') {
      unawaited(_read());
    }
  }

  void _say(String? reason, {DateTime? from}) => setState(() {
    _actionReason = reason;
    _actionFrom = from;
  });

  Future<void> _swap(DatingSwap swap) async {
    final account = _account;
    final DatingChatAnswer r;
    if (swap.mine) {
      // M-5: offline, Cancel waits (nothing is queued).
      if (!_online) {
        _say('offline');
        return;
      }
      r = await _gateway.withdrawSwap(widget.matchId);
    } else {
      if (!await showDatingSwapSheet(context, account: account)) return;
      if (!mounted || _account != account) return;
      if (!_online) {
        _say('offline');
        return;
      }
      r = await _gateway.offerSwap(widget.matchId);
    }
    if (!mounted || _account != account) return;
    // The send's reason map; already_swapped needs no line (the read shows
    // Contacts are visible now); too_early says from when.
    _say(
      r.ok || r.reason == 'already_swapped' ? null : r.reason,
      from: r.reason == 'too_early' ? r.from : null,
    );
    // unavailable: messages are paused, the chat is open; never read again.
    if (r.reason != 'unavailable') unawaited(_read());
  }

  /// Spec 2 W7a (§3.7): the report sheet sends it. Reported from a [card],
  /// the card goes from this chat at once, by id (W6 carry T4: a re-read
  /// only adds cards, so a reported one is removed here). With "Also
  /// block", this side has blocked: as Block.
  Future<void> _report(String name, {DatingSafetyCard? card}) async {
    final account = _account;
    final outcome = await showDatingReportSheet(
      context,
      account: account,
      name: name,
      target: DatingReportMatch(widget.matchId),
    );
    if (outcome == null || !mounted || _account != account) return;
    setState(() {
      if (card != null) {
        _dismissedCards.add(card.id);
        _cards.remove(card.id);
      }
      if (outcome.blocked) {
        _blockedName = name;
        _composer.clear();
        _outgoing.clear();
      }
    });
    if (card != null && account != null) {
      _pendingDismissals(account).add(card.id);
      if (_online) unawaited(_sendDismissals(account));
    }
    unawaited(_read());
  }

  /// §3.6 Block: confirmed, then sent once (from the Safety sheet or a
  /// card).
  Future<void> _block(String name) async {
    final account = _account;
    if (!await showDatingBlockSheet(context, account: account, name: name)) {
      return;
    }
    if (!mounted || _account != account) return;
    final r = await _gateway.block(
      _keys.keyFor('block', widget.matchId),
      widget.matchId,
    );
    _keys.settle('block', reason: r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      _actionReason = r.ok ? null : r.reason;
      _actionFrom = null;
      if (r.ok) {
        _blockedName = name;
        _composer.clear();
        _outgoing.clear();
      }
    });
    unawaited(_read());
  }

  /// §3.6: Dismiss hides the card (detection never changes). M-1: it
  /// stays hidden until the server confirms; offline, the line says why
  /// and it goes on the next good read.
  void _dismiss(DatingSafetyCard card) {
    final account = _account;
    if (account == null) return;
    setState(() {
      _dismissedCards.add(card.id);
      _cards.remove(card.id);
    });
    _pendingDismissals(account).add(card.id);
    if (!_online) {
      _say('offline');
      return;
    }
    unawaited(_sendDismissals(account));
  }

  /// M-2: the card's number, called after S1's confirm.
  Future<void> _call(String phone) async {
    final account = _account;
    if (!await showDatingCallSheet(context, account: account, number: phone)) {
      return;
    }
    if (!mounted || _account != account) return;
    await ref.read(supportLauncherProvider)(
      context,
      'tel:${supportDialString(phone)}',
    );
  }

  Future<void> _safety(DatingChatHeader header) async {
    final account = _account;
    final name = header.displayName;
    final choice = await showDatingSafetySheet(
      context,
      account: account,
      name: name,
      ended: header.ended || _blockedName != null,
      weMet: header.weMet,
      // M-7: just blocked here: Block is not offered again.
      blocked: _blockedName != null,
      // Spec 2 W9 (§3.9; carry 6): either side's We met, nothing asked yet.
      canLink:
          (header.weMet || header.theyMet) &&
          header.link?.state == DatingLinkState.none,
    );
    if (!mounted || _account != account || choice == null) return;
    switch (choice) {
      case DatingSafetyChoice.report:
        await _report(name);
      case DatingSafetyChoice.block:
        await _block(name);
      case DatingSafetyChoice.unmatch:
        if (!await showDatingUnmatchSheet(
          context,
          account: account,
          name: name,
        )) {
          return;
        }
        if (!mounted || _account != account) return;
        final r = await _gateway.unmatch(
          _keys.keyFor('unmatch', widget.matchId),
          widget.matchId,
        );
        _keys.settle('unmatch', reason: r.reason);
        if (!mounted || _account != account) return;
        _say(r.ok ? null : r.reason);
        unawaited(_read());
      case DatingSafetyChoice.resources:
        unawaited(context.push(RouteNames.safetyResources));
      case DatingSafetyChoice.planMeet:
        _planMeet();
      case DatingSafetyChoice.closeKindly:
        await _closeKindly();
      case DatingSafetyChoice.weMet:
        // Offline, We met waits (nothing is queued).
        if (!_online) {
          _say('offline');
          return;
        }
        final r = await _gateway.weMet(widget.matchId);
        if (!mounted || _account != account) return;
        // Fix round 1: "Noted that you met." (never whether they're told).
        _say(r.ok ? 'we_met' : r.reason);
        unawaited(_read());
      case DatingSafetyChoice.becomeCouple:
        await _openLink();
    }
  }

  /// Spec 2 W9 (§3.9): the link page; the chat reads again on return.
  Future<void> _openLink() async {
    await context.push(DatingPaths.link(widget.matchId));
    if (mounted) unawaited(_read());
  }

  /// Spec 2 W9: the asker takes the request back (from the top card).
  Future<void> _takeBack(String requestId) async {
    final account = _account;
    if (_takingBack) return;
    if (!_online) {
      _say('offline');
      return;
    }
    setState(() => _takingBack = true);
    final r = await ref.read(datingLinkGatewayProvider).cancel(requestId);
    if (!mounted || _account != account) return;
    setState(() => _takingBack = false);
    // Moved on already (answered, lapsed or linked): the re-read says so.
    _say(
      r.ok || r.reason == 'request_unavailable' || r.reason == 'linked'
          ? null
          : r.reason,
    );
    unawaited(_read());
  }

  /// Spec 2 W9 final client fix (M-3): the asker's "You decided together."
  /// shows under this ended chat.
  bool get _linkMoment {
    final page = _page;
    final h = page?.header;
    return page != null &&
        page.ok &&
        h != null &&
        _blockedName == null &&
        h.ended &&
        h.link?.state == DatingLinkState.linked &&
        h.link!.moment;
  }

  /// Spec 2 W9 (§3.9 step 4; final client fix M-3): the moment answered,
  /// by Continue or by back (as on the link page): marked seen (bounded),
  /// then the Relationship home; once.
  Future<void> _linkDone() async {
    if (_linkLeaving) return;
    _linkLeaving = true;
    await datingLinkDone(context, seen: true);
    if (mounted) _linkLeaving = false;
  }

  /// Spec 2 W6c Task 10 (§3.6): the meeting kit.
  void _planMeet() {
    unawaited(context.push(DatingPaths.plan(widget.matchId)));
  }

  /// §3.6 Close kindly: the reviewed message, confirmed, then the chat ends
  /// for both. From the day-21 card, that card is answered once the person
  /// chose Send and end (Cancel keeps it).
  Future<void> _closeKindly({bool day21 = false}) async {
    if (_closing) return;
    _closing = true;
    try {
      final account = _account;
      if (!await showDatingCloseKindlySheet(context, account: account)) return;
      if (!mounted || _account != account) return;
      if (!_online) {
        _say('offline');
        return;
      }
      final r = await _gateway.closeKindly(
        _keys.keyFor('close', widget.matchId),
        widget.matchId,
      );
      _keys.settle('close', reason: r.reason);
      if (!mounted || _account != account) return;
      // Fix round 1 (M-2): the day-21 card is answered once the chat closed.
      if (day21 && r.ok) _timebox('day21');
      _say(r.ok ? null : r.reason);
      unawaited(_read());
    } finally {
      _closing = false;
    }
  }

  /// §3.6: the timebox card is answered once. Fix round 1 (M-3): it stays
  /// hidden until the server confirms; offline, the line says why and it
  /// goes on the next good read (as a safety card's Dismiss).
  void _timebox(String card) {
    final account = _account;
    if (account == null) return;
    setState(() => _timeboxDone = card);
    _pendingTimeboxes(account).add('${widget.matchId}|$card');
    if (!_online) {
      _say('offline');
      return;
    }
    unawaited(_sendTimeboxes(account));
  }

  /// M-3: [account]'s timebox dismissals the server has not confirmed.
  Set<String> _pendingTimeboxes(String account) =>
      ref.read(datingPendingTimeboxDismissalsProvider(account));

  /// M-3: sends this chat's timebox dismissals not yet confirmed, once per
  /// pass; a confirmed one is forgotten, a failed one waits for the next
  /// read.
  Future<void> _sendTimeboxes(String account) async {
    if (_sendingTimeboxesFor == account) return;
    _sendingTimeboxesFor = account;
    final pending = _pendingTimeboxes(account);
    final prefix = '${widget.matchId}|';
    try {
      for (final entry in pending.where((e) => e.startsWith(prefix)).toList()) {
        if (!mounted || _account != account) break;
        final card = entry.substring(prefix.length);
        if (await _gateway.dismissTimebox(widget.matchId, card)) {
          pending.remove(entry);
        }
      }
    } finally {
      if (_sendingTimeboxesFor == account) _sendingTimeboxesFor = null;
    }
  }

  /// I-3: what was written for a question that moved on goes to the
  /// composer (as a message it can still be sent), after what is there.
  void _toComposer(String text) {
    final now = _composer.text;
    _composer.text = now.trim().isEmpty ? text : '$now\n$text';
  }

  /// §3.6 Answer: the sheet, then this side's answer (refused or offline,
  /// what was written is offered again next time).
  Future<void> _answer(String questionId) async {
    if (_guidedBusy) return;
    final account = _account;
    final loc = AppLocalizations.of(context)!;
    setState(() => _guidedBusy = true);
    // C-7: answered, the card waits for the read (it frees the buttons).
    var waits = false;
    try {
      final text = await showDatingGuidedAnswerSheet(
        context,
        account: account,
        question: datingGuidedQuestion(loc, questionId),
        initial: _guidedDrafts[questionId],
        // M-9: closed without Send (a swipe, Cancel, the lock), what was
        // written is offered again next time (memory only, this account).
        onDraft: (draft) {
          if (!mounted || _account != account) return;
          if (draft.trim().isEmpty) {
            _guidedDrafts.remove(questionId);
          } else {
            _guidedDrafts[questionId] = draft;
          }
        },
      );
      if (text == null || !mounted || _account != account) return;
      if (!_online) {
        _guidedDrafts[questionId] = text;
        _say('offline');
        return;
      }
      final r = await _gateway.answerGuided(
        _keys.keyFor('guided', [widget.matchId, questionId, text]),
        widget.matchId,
        questionId,
        text,
      );
      // As a message: `unavailable` (paused; nothing kept) settles as busy.
      _keys.settle(
        'guided',
        reason: r.reason == 'unavailable' ? 'busy' : r.reason,
      );
      if (!mounted || _account != account) return;
      setState(() {
        if (r.ok) {
          _guidedDrafts.remove(questionId);
          // C-7: answered. The card changes once the read below lands (the
          // waiting line, or the next question when the other person had
          // already answered); a read already on its way is dropped.
          _guidedReads++;
          _guidedAnswered = questionId;
          waits = true;
        } else if (r.reason == 'invalid' || r.reason == 'closed') {
          // Fix round 1 (I-3): the question moved on (the other skipped or
          // answered it while this was written), or the chat ended: no
          // error, and what was written goes to the composer.
          _guidedDrafts.remove(questionId);
          _toComposer(text);
        } else {
          _guidedDrafts[questionId] = text;
        }
        _actionReason =
            r.ok || r.reason == 'invalid' || r.reason == 'closed'
                ? null
                : r.reason;
        _actionFrom = null;
      });
      unawaited(_read());
    } finally {
      if (!waits && mounted && _account == account) {
        setState(() => _guidedBusy = false);
      }
    }
  }

  /// §3.6 Skip this one: skipped for both. `invalid` means the question had
  /// already moved on (the other person answered or skipped it): the read
  /// shows where it is, with no line.
  Future<void> _skip(String questionId) async {
    if (_guidedBusy) return;
    if (!_online) {
      _say('offline');
      return;
    }
    final account = _account;
    setState(() => _guidedBusy = true);
    final r = await _gateway.skipGuided(widget.matchId, questionId);
    if (!mounted || _account != account) return;
    setState(() {
      _guidedBusy = false;
      _actionReason = r.ok || r.reason == 'invalid' ? null : r.reason;
      _actionFrom = null;
    });
    unawaited(_read());
  }

  /// §3.6: the timebox card, then the guided card (and its tip), at the top.
  List<Widget> _topCards(
    BuildContext context,
    AppLocalizations loc,
    DatingChatHeader h,
  ) {
    final theme = Theme.of(context);
    final name =
        h.displayName.isEmpty ? loc.dating_cardThisPerson : h.displayName;
    Widget card(String id, String key, List<Widget> children) => _TopCard(
      key: ValueKey('dating_top_$id'),
      id: id,
      shown: _shownTop,
      child: Container(
        key: ValueKey(key),
        margin: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          0,
        ),
        padding: const EdgeInsets.all(Spacing.md),
        // M-6: the safety card's surface and hairline (no shield), never an
        // incoming bubble's fill.
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadiusTokens.mdAll,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    Widget title(String text) => Semantics(
      header: true,
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget actions(List<Widget> buttons) => Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        children: buttons,
      ),
    );
    // 4.5:1 on the card in both themes: onSurface, not the theme's green.
    Widget button(String key, String label, VoidCallback? onPressed) =>
        TextButton(
          key: ValueKey(key),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: theme.colorScheme.onSurface,
          ),
          onPressed: onPressed,
          child: Text(label),
        );
    final out = <Widget>[];
    // Spec 2 W9 (§3.9 steps 2-4): the couple link, above everything else.
    final link = h.link;
    switch (link?.state) {
      case DatingLinkState.askedYou:
        out.add(
          card('link:asked_you', 'dating_link_card', [
            title(loc.dating_linkAskedYou(name)),
            actions([
              button('dating_link_see', loc.dating_linkSee, () => unawaited(_openLink())),
            ]),
          ]),
        );
      case DatingLinkState.asked:
        out.add(
          card('link:asked', 'dating_link_card', [
            title(loc.dating_linkAsked(name)),
            actions([
              button(
                'dating_link_take_back',
                loc.dating_linkTakeBack,
                _takingBack ? null : () => unawaited(_takeBack(link!.requestId!)),
              ),
            ]),
          ]),
        );
      case DatingLinkState.notReady:
        out.add(card('link:not_ready', 'dating_link_card', [title(loc.dating_linkNotReady(name))]));
      // A linked chat has ended: its moment is under the chat (lines).
      case _:
        break;
    }
    final pendingBoxes =
        _account == null ? const <String>{} : _pendingTimeboxes(_account!);
    final timebox =
        h.timebox == _timeboxDone ||
                pendingBoxes.contains('${widget.matchId}|${h.timebox}')
            ? null
            : h.timebox;
    if (timebox == 'day7') {
      out.add(
        card('timebox:day7', 'dating_timebox_day7', [
          title(loc.dating_timeboxDay7),
          actions([
            button(
              'dating_timebox_not_yet',
              loc.dating_timeboxNotYet,
              () => _timebox('day7'),
            ),
            // Spec 2 W6c Task 10 (§3.6): Plan a meet answers the card too.
            button('dating_timebox_plan', loc.dating_planTitle, () {
              _timebox('day7');
              _planMeet();
            }),
          ]),
        ]),
      );
    } else if (timebox == 'day21') {
      out.add(
        card('timebox:day21', 'dating_timebox_day21', [
          title(loc.dating_timeboxDay21),
          actions([
            button(
              'dating_timebox_keep',
              loc.dating_timeboxKeep,
              () => _timebox('day21'),
            ),
            button(
              'dating_timebox_close',
              loc.dating_closeKindly,
              () => unawaited(_closeKindly(day21: true)),
            ),
          ]),
        ]),
      );
    }
    final q = _guided.questionId;
    final busy = _guidedBusy;
    if (q != null) {
      out.add(
        card('guided:$q:${_guided.answered}', 'dating_guided', [
          title(loc.dating_guidedTitle),
          const SizedBox(height: Spacing.xs),
          Text(datingGuidedQuestion(loc, q), style: theme.textTheme.bodyLarge),
          if (_guided.answered)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                h.displayName.isEmpty
                    ? loc.dating_guidedWaitingNoName
                    : loc.dating_guidedWaiting(name),
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            actions([
              button(
                'dating_guided_skip',
                loc.dating_guidedSkip,
                busy ? null : () => _skip(q),
              ),
              // C-8 (T9 M-7): Answer carries the weight; Skip stays plain.
              FilledButton.tonal(
                key: const ValueKey('dating_guided_answer_button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: busy ? null : () => _answer(q),
                child: Text(loc.dating_guidedAnswer),
              ),
            ]),
        ]),
      );
    }
    // §3.6: after the first reveal, once (fix round 1, I-4: until this
    // side next writes; never once the questions are done).
    if (_tipDue) {
      out.add(
        _TopCard(
          key: const ValueKey('dating_top_tip'),
          id: 'tip',
          shown: _shownTop,
          child: Padding(
            key: const ValueKey('dating_guided_tip'),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              0,
            ),
            child: Text(
              loc.dating_guidedTip(name),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    return out;
  }

  /// I-4: the tip is due after the first reveal until this side next
  /// writes (a message after the revealed pair, or one on its way), and
  /// never once the questions are done. Fix round 2: with the pair not
  /// among the messages read and older pages to load, the pair is older
  /// than all of them, so any of this side's is after it (no tip); with no
  /// page missing it still shows (Ruling F5, narrowed).
  bool get _tipDue {
    if (_guided.revealed != 1 || _guided.questionId == null) return false;
    if (_outgoing.any((o) => !o.failed)) return false;
    final answers = <String, List<DatingChatMessage>>{};
    for (final m in _held.values) {
      final q = m.questionId;
      if (m.kind == 'guided_answer' && q != null) {
        (answers[q] ??= []).add(m);
      }
    }
    final pair = answers.values.where(
      (a) => a.any((m) => m.mine) && a.any((m) => !m.mine),
    );
    if (pair.isEmpty) return !(_more && _held.values.any((m) => m.mine));
    final revealed = pair.first
        .map((m) => m.at)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final ids = {for (final m in pair.first) m.id};
    return !_held.values.any(
      (m) => m.mine && !ids.contains(m.id) && m.at.isAfter(revealed),
    );
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    return MyDateFormat.join([
      MyDateFormat.toDateShort(local),
      MyDateFormat.toTime(local),
    ]);
  }

  String _reasonLine(AppLocalizations loc, String? reason) => switch (reason) {
    'closed' => loc.dating_chatEnded,
    'restricted' => loc.dating_chatRestricted,
    'rate_limited' => loc.dating_errorRateLimited,
    'busy' => loc.dating_busy,
    'match_unavailable' => loc.dating_cardGone,
    // Task 2 fix round 1b: messages are paused (retryable; not ended).
    'unavailable' => loc.dating_chatPaused,
    // Fix round 1: We met's calm line (not a refusal).
    'we_met' => loc.dating_weMetNoted,
    'offline' => loc.dating_offline,
    _ => loc.dating_errorGeneric,
  };

  /// A line under the chat: the re-check for reverify_device, an error
  /// (icon and text) for a failure, otherwise a calm line.
  Widget _line(AppLocalizations loc, String reason, {String? text}) =>
      switch (reason) {
        'reverify_device' => const DatingReverifyLine(),
        'failed' || 'invalid' => Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        ),
        _ => DatingCalmLine(text ?? _reasonLine(loc, reason)),
      };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    // A chat signal: read again (the other person wrote, swapped, or ended
    // it). Fallback poll: only while this chat is on top and not already
    // reading. Either, only for the account it was listened for (D8: the
    // last account's entry never reads as the next one).
    _route = ModalRoute.of(context);
    final listened = _account;
    ref.listen(datingChatSignalsProvider(listened), (previous, next) {
      if (listened != _account) return;
      if (next.reads != previous?.reads) {
        unawaited(_read());
      } else if (next.polls != previous?.polls && _pollDue) {
        unawaited(_read());
      }
    });
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final page = _page;
    final header = page?.header;
    final name = header?.displayName ?? '';
    final title =
        header == null
            ? ''
            : name.isEmpty
            ? loc.dating_chatTitleNoName
            : header.age == null
            ? name
            : loc.dating_chatTitle(name, header.age!);
    // Spec 2 W9 final client fix (M-3): while the moment shows, back
    // answers it (the Relationship home), as Continue.
    final linkMoment = _linkMoment;
    final rootBack = datingRootBackButton(context);
    return AllowLargeText(
      child: DatingOwnBack(
        active: linkMoment,
        onBack: () => unawaited(_linkDone()),
        child: Scaffold(
        appBar: AppBar(
          // Fix round 1 (I-3): the only page goes back to Conversations.
          // Final client fix (M-3): as the only page, its back answers the
          // moment too (pushed, the AppBar's own back pops through
          // DatingOwnBack).
          leading:
              linkMoment && rootBack != null
                  ? BackButton(
                    key: const ValueKey('dating_link_back_home'),
                    onPressed: () => unawaited(_linkDone()),
                  )
                  : rootBack,
          title: Semantics(header: true, child: Text(title)),
          actions: [
            if (header != null)
              Semantics(
                button: true,
                label: loc.dating_chatSafetyLabel,
                excludeSemantics: true,
                onTap: () => _safety(header),
                child: IconButton(
                  key: const ValueKey('dating_chat_safety'),
                  icon: const Icon(Icons.shield_outlined),
                  tooltip: loc.dating_chatSafetyLabel,
                  onPressed: () => _safety(header),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.chat,
            child: switch (page) {
              null => const Center(child: CircularProgressIndicator()),
              DatingChatPage(ok: false) => ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [_refusal(loc, page.reason, online)],
              ),
              _ => _chat(context, loc, header!, online),
            },
          ),
        ),
      ),
      ),
    );
  }

  Widget _refusal(AppLocalizations loc, String? reason, bool online) {
    final retry = FlowSecondaryButton(
      label: loc.dating_tryAgain,
      onPressed: () => unawaited(_read()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (reason) {
        _ when !online => [DatingCalmLine(loc.dating_offline), retry],
        'reverify_device' => [const DatingReverifyLine()],
        'match_unavailable' => [DatingCalmLine(loc.dating_cardGone)],
        'busy' => [DatingCalmLine(loc.dating_busy), retry],
        _ => [
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          retry,
        ],
      },
    );
  }

  Widget _chat(
    BuildContext context,
    AppLocalizations loc,
    DatingChatHeader header,
    bool online,
  ) {
    final messages = _messages;
    final cards = _cards.values.toList();
    final name = header.displayName;
    final ended = header.ended || _blockedName != null;
    final readReason = _readReason;
    final actionReason = _actionReason;
    final actionFrom = _actionFrom;
    final lines = [
      if (readReason != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Spacing.sm,
            children: [
              _line(loc, online ? readReason : 'offline'),
              FlowTextLink(
                label: loc.dating_tryAgain,
                onPressed: () => unawaited(_read()),
              ),
            ],
          ),
        ),
      if (actionReason != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: _line(
            loc,
            actionReason,
            text:
                actionReason == 'too_early' && actionFrom != null
                    ? loc.dating_chatSwapFrom(_when(actionFrom))
                    : null,
          ),
        ),
      if (_blockedName != null)
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: DatingCalmLine(
            _blockedName!.isEmpty
                ? loc.dating_blockDoneNoName
                : loc.dating_blockDone(_blockedName!),
          ),
        )
      // Spec 2 W9 (§3.9 step 4; R-W9-3): the couple linked (this chat
      // ended with it) and the moment is still to show: in the ended
      // line's place.
      else if (ended &&
          header.link?.state == DatingLinkState.linked &&
          header.link!.moment)
        Padding(
          key: const ValueKey('dating_link_card'),
          padding: const EdgeInsets.all(Spacing.md),
          // Fix round 1 (I-1): marked seen (bounded) before the
          // Relationship home reads its card.
          child: DatingLinkMoment(onContinue: _linkDone),
        )
      else if (ended)
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: DatingCalmLine(loc.dating_chatEnded),
        )
      else ...[
        // Final client fix (M-13): a send or an action refused as
        // restricted leads to why (the restricted screen).
        if (actionReason == 'restricted' ||
            _outgoing.any((o) => o.failed && o.reason == 'restricted'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: FlowTextLink(
              key: const ValueKey('dating_chat_see_why'),
              label: loc.dating_restrictedSeeWhy,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.restricted),
            ),
          ),
        _composerRow(context, loc, online),
      ],
    ];
    // M-12: at large text with the keyboard up, the swap row and the lines
    // under the chat each take at most a share of the height and scroll
    // inside it (the composer, last, stays in view); the messages keep the
    // rest. Fix round 1 (I-1): with the keyboard up the top cards step
    // aside (they come back when it closes; the shown set never replays
    // them); with it down the top area takes what it needs up to 0.65,
    // with a scrollbar when there is more.
    return LayoutBuilder(
      builder: (context, box) {
        final keyboard =
            MediaQuery.viewInsetsOf(context).bottom > 0 ||
            View.of(context).viewInsets.bottom > 0;
        final topCards =
            keyboard ? const <Widget>[] : _topCards(context, loc, header);
        return CustomMultiChildLayout(
          delegate: _ChatColumn(topShare: topCards.isEmpty ? 0.25 : 0.65),
          children: [
            if (!ended)
              LayoutId(
                key: const ValueKey('dating_chat_top'),
                id: 'top',
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _topMetrics,
                  child: Scrollbar(
                    controller: _topScroll,
                    thumbVisibility: topCards.isNotEmpty && _topOverflows,
                    child: SingleChildScrollView(
                      controller: _topScroll,
                      padding: EdgeInsets.only(
                        bottom: topCards.isEmpty ? 0 : Spacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_swapRow(context, loc, header), ...topCards],
                      ),
                    ),
                  ),
                ),
              ),
            LayoutId(
              id: 'messages',
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: ListView(
                  key: const ValueKey('dating_chat_messages'),
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  children: [
                    for (final o in _outgoing.reversed) _outgoingBubble(loc, o),
                    // Fix round 1 (I-2): a guided answer, or a revealed
                    // pair, is one entry under its question.
                    for (final entry in _entries(messages)) ...[
                      // §3.6: a card shows under the message that raised
                      // it (the list is reversed: the first raised sits
                      // nearest the message).
                      for (final m in entry)
                        for (final c in cards.reversed)
                          if (c.messageId == m.id)
                            DatingSafetyCardView(
                              key: ValueKey('dating_card_${c.id}'),
                              card: c,
                              name: name,
                              ended: ended,
                              // I-1: new to this open chat only once.
                              shown: _shownCards,
                              onBlock: () => _block(name),
                              onReport: () => _report(name, card: c),
                              onDismiss: () => _dismiss(c),
                              onCall: _call,
                              onPlanMeet: _planMeet,
                              onResources:
                                  () => unawaited(
                                    context.push(RouteNames.safetyResources),
                                  ),
                            ),
                      if (entry.first.kind == 'guided_answer')
                        _guidedBlock(context, loc, entry, name)
                      else
                        _bubble(context, loc, entry.first, name),
                    ],
                    if (_more) _olderRow(loc, online),
                  ],
                ),
              ),
            ),
            LayoutId(
              id: 'lines',
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: lines,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// I-1: whether the top area has more than it shows (after the frame:
  /// a metrics change arrives during layout).
  bool _topMetrics(ScrollMetricsNotification n) {
    final more = n.metrics.maxScrollExtent > 0;
    if (more != _topOverflows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _topOverflows = more);
      });
    }
    return false;
  }

  /// Fix round 1 (I-2): the messages as entries, newest first: one message
  /// each, but a question's guided answers (one waiting, or the revealed
  /// pair the server places together) are one entry where the first sits.
  List<List<DatingChatMessage>> _entries(List<DatingChatMessage> messages) {
    final out = <List<DatingChatMessage>>[];
    final guided = <String, List<DatingChatMessage>>{};
    for (final m in messages) {
      final q = m.questionId;
      if (m.kind != 'guided_answer' || q == null) {
        out.add([m]);
      } else if (guided[q] case final entry?) {
        entry.add(m);
      } else {
        out.add(guided[q] = [m]);
      }
    }
    return out;
  }

  /// I-2: a question's answers under it as a caption ("What does a good
  /// Saturday look like for you?"), theirs then this side's; read as the
  /// question, then each answer with its sender.
  Widget _guidedBlock(
    BuildContext context,
    AppLocalizations loc,
    List<DatingChatMessage> answers,
    String name,
  ) {
    final theme = Theme.of(context);
    final question = datingGuidedQuestion(loc, answers.first.questionId ?? '');
    final ordered = [
      ...answers.where((m) => !m.mine),
      ...answers.where((m) => m.mine),
    ];
    return Semantics(
      key: ValueKey('dating_guided_pair_${answers.first.questionId}'),
      container: true,
      explicitChildNodes: true,
      label: question.isEmpty ? null : question,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (question.isNotEmpty)
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Flexible(
                        child: Text(
                          question,
                          key: const ValueKey('dating_guided_caption'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final m in ordered) _bubble(context, loc, m, name),
          ],
        ),
      ),
    );
  }

  /// M-11: "Show earlier messages", its progress, and why it failed.
  Widget _olderRow(AppLocalizations loc, bool online) {
    final reason = _olderReason;
    return Column(
      children: [
        if (_loadingOlder)
          Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Semantics(
              label: loc.dating_chatLoadOlder,
              child: const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Center(
            child: FlowTextLink(
              label: loc.dating_chatLoadOlder,
              onPressed: () => unawaited(_loadOlder()),
            ),
          ),
        if (reason != null && !_loadingOlder)
          _line(loc, online ? reason : 'offline'),
      ],
    );
  }

  Widget _swapRow(
    BuildContext context,
    AppLocalizations loc,
    DatingChatHeader h,
  ) {
    final s = h.swap;
    final name = h.displayName;
    final theme = Theme.of(context);
    Widget line(String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.xs, Spacing.md, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Spacing.sm,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
          if (action != null) action,
        ],
      ),
    );
    // A chip sizes its height from its label laid out on one line and fades
    // the rest; capping the label's width first lets large text wrap (the
    // icon's box is fixed so it never takes the label's room).
    Widget chip(String label, {required bool enabled}) => LayoutBuilder(
      builder:
          (context, box) => ActionChip(
            key: const ValueKey('dating_chat_swap'),
            avatar: const Icon(Icons.swap_horiz, size: 18),
            avatarBoxConstraints: const BoxConstraints.tightFor(
              width: 18,
              height: 18,
            ),
            label: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (box.maxWidth - 64).clamp(48, double.infinity),
              ),
              child: Text(
                label,
                maxLines: 4,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
            onPressed: enabled ? () => _swap(s) : null,
          ),
    );
    if (s.both) return line(loc.dating_chatSwapDone);
    if (s.mine) {
      return line(
        name.isEmpty
            ? loc.dating_chatSwapOfferedNoName
            : loc.dating_chatSwapOffered(name),
        FlowTextLink(
          label: loc.dating_chatSwapCancel,
          onPressed: () => _swap(s),
        ),
      );
    }
    if (s.theirs) {
      return line(
        name.isEmpty
            ? loc.dating_chatSwapTheirsNoName
            : loc.dating_chatSwapTheirs(name),
        chip(loc.dating_chatSwap, enabled: true),
      );
    }
    final from = s.from?.toLocal();
    if (from != null && _now.isBefore(s.from!)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.xs,
          Spacing.md,
          0,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: chip(loc.dating_chatSwapFrom(_when(from)), enabled: false),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.xs, Spacing.md, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: chip(loc.dating_chatSwap, enabled: true),
      ),
    );
  }

  /// A message's words, each hidden span "•••" (read as "hidden contact
  /// detail"; the whole bubble, tapped, says what it means). Final client
  /// fix (I-2): one text that flows, each span inline (a Wrap of texts
  /// broke the line at every span).
  Widget _words(String text, TextStyle? style) {
    final parts = datingMaskedParts(text);
    if (parts.every((p) => !p.$2)) return Text(text, style: style);
    // Each span its own key (two spans with one key would throw): the first
    // keeps 'dating_chat_masked', the rest carry their place.
    var spans = 0;
    return Text.rich(
      TextSpan(
        children: [
          for (final (part, masked) in parts)
            if (masked)
              WidgetSpan(
                // On the line's baseline, so a span never changes its height.
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Padding(
                  key: ValueKey(
                    spans++ == 0
                        ? 'dating_chat_masked'
                        : 'dating_chat_masked_$spans',
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    kDatingMask,
                    // The span is scaled with its line already.
                    textScaler: TextScaler.noScaling,
                    style: style?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              TextSpan(text: part),
        ],
      ),
      style: style,
    );
  }

  String _spoken(AppLocalizations loc, String text) =>
      [
        for (final (part, masked) in datingMaskedParts(text))
          masked ? ' ${loc.dating_chatMaskedLabel} ' : part,
      ].join().replaceAll(RegExp(' {2,}'), ' ').trim();

  bool _isMasked(String text) => datingMaskedParts(text).any((p) => p.$2);

  void _explain() => showDatingMaskedSheet(context, account: _account);

  /// A bubble's face. Masked (M-9): the whole bubble is the target, at
  /// least 48 high, and it says what the hidden spans are.
  Widget _face({required String id, required String text, required bool mine}) {
    final theme = Theme.of(context);
    final color =
        mine
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    final onColor =
        mine
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;
    final words = _words(
      text,
      theme.textTheme.bodyLarge?.copyWith(color: onColor),
    );
    const padding = EdgeInsets.symmetric(
      horizontal: Spacing.md,
      vertical: Spacing.sm,
    );
    // C-3: one rhythm: every bubble sits in the same vertical padding.
    const rhythm = EdgeInsets.symmetric(vertical: Spacing.xs);
    if (!_isMasked(text)) {
      return Container(
        key: ValueKey('dating_chat_bubble_$id'),
        margin: rhythm,
        padding: padding,
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadiusTokens.lgAll,
        ),
        child: words,
      );
    }
    // The target is the bubble with its padding (at least 48 high); the
    // bubble itself is as high as a plain one.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('dating_chat_bubble_$id'),
        borderRadius: BorderRadiusTokens.lgAll,
        onTap: _explain,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: rhythm,
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Ink(
                  padding: padding,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadiusTokens.lgAll,
                  ),
                  child: words,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(
    BuildContext context,
    AppLocalizations loc,
    DatingChatMessage m,
    String name,
  ) {
    final sender =
        m.mine
            ? loc.dating_chatYou
            : (name.isEmpty ? loc.dating_chatThem : name);
    // Fix round 1 (M-1): Close kindly's message in the app's words (the
    // ones the sender confirmed), never the server's English copy.
    final text =
        m.kind == 'close_kindly' ? loc.dating_closeKindlyMessage : m.text;
    final masked = _isMasked(text);
    // Read as one line with its sender; a hidden span reads "hidden contact
    // detail", and the message, tapped, says what that means.
    return Semantics(
      container: true,
      label: '$sender: ${_spoken(loc, text)}',
      button: masked,
      excludeSemantics: true,
      onTap: masked ? _explain : null,
      child: Align(
        alignment:
            m.mine
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
        child: _face(id: m.id, text: text, mine: m.mine),
      ),
    );
  }

  /// M-6: what a refused send says. Final refusals are never offered
  /// again: "Not sent." (the banner or the page says why), or restricted's
  /// own line; the rest say why when they have their own line, then "Not
  /// sent. Tap to try again."
  List<String> _failedLines(AppLocalizations loc, String? reason) => [
    if (reason == 'restricted')
      loc.dating_chatRestricted
    else if (_finalRefusals.contains(reason))
      loc.dating_chatNotSentFinal
    else ...[
      if (_namedRetryable.contains(reason)) _reasonLine(loc, reason),
      loc.dating_chatNotSent,
    ],
  ];

  Widget _outgoingBubble(AppLocalizations loc, _Outgoing o) {
    final theme = Theme.of(context);
    final shown = o.shown ?? o.text;
    // §3.6: "Sending…", then nothing.
    final lines =
        o.failed
            ? _failedLines(loc, o.reason)
            : [if (o.sentId == null) loc.dating_chatSending];
    final small = theme.textTheme.bodySmall;
    final bubble = Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sent: the server's copy (masked too, §6.1), never what was typed.
          _face(id: o.sentId ?? o.key, text: shown, mine: true),
          if (lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs, top: 2),
              // M-7: a failure is an icon and its words.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (o.failed) ...[
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final line in lines)
                          Text(
                            line,
                            textAlign: TextAlign.end,
                            style: small?.copyWith(
                              color:
                                  o.failed
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final label = [
      '${loc.dating_chatYou}: ${_spoken(loc, shown)}.',
      ...lines,
    ].join(' ');
    if (!o.failed) {
      // M-8: read as one line; masked, a tap says what the spans are.
      final masked = _isMasked(shown);
      return Semantics(
        container: true,
        liveRegion: true,
        button: masked,
        label: label,
        excludeSemantics: true,
        onTap: masked ? _explain : null,
        child: bubble,
      );
    }
    final retry = !_finalRefusals.contains(o.reason);
    return Semantics(
      container: true,
      liveRegion: true,
      button: retry,
      label: label,
      excludeSemantics: true,
      onTap: retry ? () => _send(o) : null,
      child: InkWell(
        borderRadius: BorderRadiusTokens.lgAll,
        onTap: retry ? () => _send(o) : null,
        child: bubble,
      ),
    );
  }

  Widget _composerRow(BuildContext context, AppLocalizations loc, bool online) {
    final theme = Theme.of(context);
    // M-12: fewer lines at large text, so the composer fits with the
    // keyboard up.
    final large = MediaQuery.textScalerOf(context).scale(10) > 15;
    return Padding(
      // C-4: mirrored right to left (the field's edge, the button's edge).
      padding: const EdgeInsetsDirectional.fromSTEB(
        Spacing.md,
        Spacing.xs,
        Spacing.xs,
        Spacing.sm,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _composer,
        builder: (context, value, _) {
          // M-10: counted as the server counts; near the limit a counter,
          // over it a line and no Send.
          final count = datingMessageLength(value.text);
          final over = count > kDatingMessageMax;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_offlineTried && !online)
                DatingCalmLine(loc.dating_chatOffline),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: FlowErrorLine(
                    text: loc.dating_chatTooLong,
                    liveRegion: true,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('dating_chat_composer'),
                      controller: _composer,
                      minLines: 1,
                      maxLines: large ? 3 : 5,
                      // A paste far past the limit stops here; the limit
                      // itself is said, never cut silently.
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kDatingMessageMax * 2),
                      ],
                      textCapitalization: TextCapitalization.sentences,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      decoration: InputDecoration(
                        hintText: loc.dating_chatComposerHint,
                        counterText:
                            count >= kDatingMessageCounterFrom
                                ? loc.dating_chatCounter(
                                  count,
                                  kDatingMessageMax,
                                )
                                : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      key: const ValueKey('dating_chat_send'),
                      tooltip: loc.dating_chatSend,
                      color: theme.colorScheme.primary,
                      icon: const Icon(Icons.send),
                      onPressed: over ? null : () => _send(null),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
