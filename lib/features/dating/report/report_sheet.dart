// Spec 2 W7a (§3.7, §3.15 Report sheet; §6.2; D8): the report sheet, from
// a conversation's Safety sheet, a safety card, the ended list or a card
// on Today. The 14 categories as one radio group with their full labels,
// "Tell us more (optional)" (500 characters, the keyboard never learns),
// "Also block {Name}" (on for P0 to P2 until the person touches it), Send
// report. Offline nothing is sent. Sent: the thanks with the review time
// (or, while no named moderator reads reports, the testing line) and the
// emergency number; after a money report, "You did the right thing." with
// Pause Dating. Never animated beyond the sheet itself; one key per sheet,
// so a retry after busy is the same report; another account on the phone
// sees nothing of it and the sheet closes.
//
// Task 3 rulings: when "Also block" didn't go through (the answer's
// `"blocked": false`) the thanks says so and the outcome is not blocked,
// so the screen still offers Block; a sent report is the outcome however
// the sheet closes (Close, back, the barrier, or a pop from outside:
// fix round 1 hands it over through the send's own future, onSending).
//
// Fix round 1 (task-3-review.md): I-1 while a report is on its way the
// sheet stays: back and the barrier do nothing, it never drags away (its
// own Close is in its corner), and the sending state shows; a pop from
// outside (the lock, quick exit, another account) still hands the opener
// the outcome once the answer lands; the request key is held per account
// and person (datingReportKeysProvider), so a sheet opened again after a
// busy answer sends the same request. I-4 the details count code points
// as the server does. M-1 an answer without its review time says no time
// (never "In testing" unless the server says testing). M-2 from the ended
// list the not-blocked line promises no retry. M-3 "What happened?" is
// read once (the group's name). M-4/M-5 the emergency number is a call
// (S1's confirm first), on the thanks and under every refusal or offline,
// with the danger line. M-7 the thanks is one live region.
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/chat/chat_sheets.dart'
    show showDatingCallSheet;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/setup/dating_text_rules.dart'
    show DatingRuneLimit;
import 'package:attune/features/dating/today/dating_today_providers.dart'
    show datingTodayProvider;
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The report sheet about [name] (empty: no name), opened as [account];
/// null when nothing was sent. [canBlockLater]: the opener still offers
/// Block (false on the ended list). A report still on its way when the
/// sheet goes is waited for (I-1).
Future<DatingReportOutcome?> showDatingReportSheet(
  BuildContext context, {
  required String? account,
  required String name,
  required DatingReportTarget target,
  bool canBlockLater = true,
}) async {
  // Spec 2 W8a round 2 (Re-1-M2): nothing opens once Dating is blank.
  if (datingSheetRefused) return null;
  Future<DatingReportOutcome?>? sending;
  // W7a Task 4 fix round 1 (K-1): a sheet removed from outside
  // (closeDatingSheets: the lock, quick exit) never completes its own
  // future (Navigator.removeRoute), so its going is told here too.
  final gone = Completer<DatingReportOutcome?>();
  void end(DatingReportOutcome? value) {
    if (!gone.isCompleted) gone.complete(value);
  }

  unawaited(
    showModalBottomSheet<DatingReportOutcome>(
      context: context,
      routeSettings: datingSheetSettings('report'),
      isScrollControlled: true,
      // I-1: never dragged away mid-send; the sheet has its own Close.
      enableDrag: false,
      // §3.15 (Task 4 fix round 1, M-7): the report sheet never animates.
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder:
          (sheet) => DatingSheetTracker(
            child: AllowLargeText(
              child: DatingReportSheet(
                account: account,
                name: name,
                target: target,
                canBlockLater: canBlockLater,
                onSending: (f) => sending = f,
                onGone: () => end(null),
              ),
            ),
          ),
    ).then(end),
  );
  final popped = await gone.future;
  if (popped != null) return popped;
  final pending = sending;
  return pending == null ? null : await pending;
}

class DatingReportSheet extends ConsumerStatefulWidget {
  const DatingReportSheet({
    super.key,
    required this.account,
    required this.name,
    required this.target,
    this.canBlockLater = true,
    this.onSending,
    this.onGone,
  });

  final String? account;
  final String name;
  final DatingReportTarget target;

  /// M-2: the opener still offers Block after a block that didn't go
  /// through (a chat, a card on Today); false on the ended list.
  final bool canBlockLater;

  /// I-1: each send's outcome (null when nothing was sent), told even when
  /// the sheet has gone before the answer lands.
  final ValueChanged<Future<DatingReportOutcome?>>? onSending;

  /// Task 4 fix round 1 (K-1): the sheet left the tree (after its own pop,
  /// or removed from outside), so the opener stops waiting on the route.
  final VoidCallback? onGone;

  @override
  ConsumerState<DatingReportSheet> createState() => _DatingReportSheetState();
}

class _DatingReportSheetState extends ConsumerState<DatingReportSheet> {
  final _details = TextEditingController();
  DatingReportCategory? _category;
  bool _block = true;
  bool _blockTouched = false;
  bool _busy = false;
  String? _reason;
  DatingReportAnswer? _sent;
  bool _pausing = false;
  bool _paused = false;

  /// Final client fix (I-2): the pause was answered (the server's state
  /// may not be paused, so nothing is claimed); Pause isn't offered again.
  bool _pauseAnswered = false;
  bool _pauseFailed = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(force: true));
    });
  }

  /// I-1: one key store per account (memory only), so a sheet opened
  /// again after busy sends the same request.
  DatingActionKeys get _keys =>
      ref.read(datingReportKeysProvider(widget.account));

  String get _action => switch (widget.target) {
    DatingReportMatch(:final id) => 'report:match:$id',
    DatingReportCard(:final id) => 'report:card:$id',
  };

  @override
  void dispose() {
    widget.onGone?.call();
    _details.dispose();
    super.dispose();
  }

  DatingReportOutcome? get _outcome => switch (_sent) {
    final sent? => DatingReportOutcome(
      blocked: _block && sent.blocked,
      alsoBlock: _block,
      category: _category,
      paused: _paused,
    ),
    null => null,
  };

  /// The sheet closes; [force] (another account) even while a report is
  /// on its way, which the person's own back or barrier never does (I-1).
  void _close({bool force = false}) {
    if (_closed || !mounted || (_busy && !force)) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(_outcome);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  void _choose(DatingReportCategory? c) {
    if (c == null || _busy) return;
    setState(() {
      _category = c;
      if (!_blockTouched) _block = c.blockByDefault;
    });
  }

  Future<void> _send() async {
    final c = _category;
    if (c == null || _busy) return;
    final account = widget.account;
    final details = _details.text.trim();
    final block = _block;
    setState(() {
      _busy = true;
      _reason = null;
    });
    // Read before the wait: the sheet may be gone when the answer lands.
    final keys = _keys;
    final action = _action;
    final key = keys.keyFor(action, [c.wire, details, block]);
    final done = Completer<DatingReportOutcome?>();
    widget.onSending?.call(done.future);
    final r = await ref
        .read(datingReportGatewayProvider)
        .report(
          key,
          widget.target,
          c,
          details.isEmpty ? null : details,
          alsoBlock: block,
        );
    keys.settle(action, reason: r.reason);
    done.complete(
      r.ok
          ? DatingReportOutcome(
            blocked: block && r.blocked,
            alsoBlock: block,
            category: c,
          )
          : null,
    );
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _sent = r;
      } else {
        _reason = r.reason;
      }
    });
  }

  Future<void> _pause() async {
    if (_pausing || _pauseAnswered) return;
    final account = widget.account;
    setState(() {
      _pausing = true;
      _pauseFailed = false;
    });
    final keys = _keys;
    // Read before the wait: the sheet may be gone when the answer lands.
    final container = ProviderScope.containerOf(context, listen: false);
    final r = await ref
        .read(datingLifecycleGatewayProvider)
        .pause(keys.keyFor('pause', account));
    keys.settle('pause', error: r.error);
    // Final client fix (I-2): the home changed (or was already paused), so
    // the section, Today and the chat read it again, whoever opened the
    // sheet and even when it has gone; "paused" only when the server says
    // so (as dating_leave_screen's fix 1).
    final answered = r.ok || r.error == DatingLifecycleError.notPaused;
    if (answered) {
      container
        ..invalidate(datingHomeProvider(account))
        ..invalidate(datingTodayProvider(account));
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _pausing = false;
      _pauseAnswered = answered;
      _paused = r.ok && r.state == 'paused';
      _pauseFailed = !answered;
    });
  }

  String _error(AppLocalizations loc, String reason) => switch (reason) {
    'rate_limited' => loc.dating_errorRateLimited,
    'report_unavailable' => loc.dating_cardGone,
    _ => loc.dating_errorGeneric,
  };

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sent = _sent;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.md + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children:
                sent == null
                    ? _choosing(context, loc, theme)
                    : _thanks(context, loc, theme, sent),
          ),
        ),
      ),
    );
  }

  List<Widget> _choosing(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
  ) {
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final name = widget.name;
    // M-4: the number is read while the person chooses, so the thanks
    // never changes its line under a screen reader.
    final number = _emergencyNumber();
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                name.isEmpty
                    ? loc.dating_reportTitleNoName
                    : loc.dating_reportTitle(name),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          // I-1: the sheet's own way out (it never drags away); off while
          // a report is on its way.
          IconButton(
            key: const ValueKey('dating_report_cancel'),
            tooltip: loc.dating_close,
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : _close,
          ),
        ],
      ),
      const SizedBox(height: Spacing.sm),
      // M-3: read once, as the group's name below.
      ExcludeSemantics(
        child: Text(loc.dating_reportWhat, style: theme.textTheme.bodyLarge),
      ),
      const SizedBox(height: Spacing.xs),
      Semantics(
        container: true,
        label: loc.dating_reportWhat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in DatingReportCategory.values)
              RadioListTile<DatingReportCategory>(
                key: ValueKey('dating_report_${c.wire}'),
                value: c,
                groupValue: _category,
                onChanged: _busy ? null : _choose,
                contentPadding: EdgeInsets.zero,
                title: Text(datingReportLabel(loc, c)),
              ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),
      // Final client fix (M-5, as the appeal sheet's M-1): the label above
      // the field, where it wraps at large text (a field's own label is one
      // line and clips "(optional)"), merged with the field so a screen
      // reader names it; the count under it.
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.dating_reportMore, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            TextField(
              key: const ValueKey('dating_report_details'),
              controller: _details,
              enabled: !_busy,
              // I-4: code points, as the server counts (never graphemes).
              inputFormatters: const [DatingRuneLimit(500)],
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              minLines: 2,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.xs),
      Text(
        loc.dating_gentleWaitAnswerCount(_details.text.runes.length, 500),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      SwitchListTile(
        key: const ValueKey('dating_report_block'),
        value: _block,
        contentPadding: EdgeInsets.zero,
        onChanged:
            _busy
                ? null
                : (v) => setState(() {
                  _block = v;
                  _blockTouched = true;
                }),
        title: Text(
          name.isEmpty
              ? loc.dating_reportBlockNoName
              : loc.dating_reportBlock(name),
        ),
      ),
      if (!online) DatingCalmLine(loc.dating_reportOffline),
      // §3.15: busy is a calm line (a retry is the same report); a refusal
      // is the theme's error line.
      if (_reason case final reason?)
        reason == 'busy'
            ? DatingCalmLine(loc.dating_busy)
            : FlowErrorLine(text: _error(loc, reason), liveRegion: true),
      // M-5: whenever the report can't go now, the way to help now.
      if (!online || _reason != null) ..._danger(loc, theme, number),
      const SizedBox(height: Spacing.sm),
      FlowPrimaryButton(
        key: const ValueKey('dating_report_send'),
        label: loc.dating_reportSend,
        busy: _busy,
        onPressed: _category != null && online && !_busy ? _send : null,
      ),
    ];
  }

  List<Widget> _thanks(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    DatingReportAnswer sent,
  ) {
    final number = _emergencyNumber();
    final hours = sent.slaHours;
    final within =
        hours == null
            ? null
            : hours < 48
            ? loc.dating_reportHours(hours)
            : loc.dating_reportDays((hours / 24).ceil());
    // M-1: the testing line only when the server says testing; an answer
    // without its review or its hours says no time.
    final line =
        !sent.reviewKnown || (!sent.testing && within == null)
            ? (number == null
                ? loc.dating_reportSentNoTimeNoNumber
                : loc.dating_reportSentNoTime(number))
            : sent.testing
            ? (number == null
                ? loc.dating_reportSentTestingNoNumber
                : loc.dating_reportSentTesting(number))
            : (number == null
                ? loc.dating_reportSentNoNumber(within!)
                : loc.dating_reportSent(within!, number));
    final scam = _category == DatingReportCategory.romanceScam;
    final name = widget.name;
    // Final client fix (I-1): a P0 card goes whatever the block did (the
    // server invalidates it), so its line promises no retry either.
    final retryLater =
        widget.canBlockLater &&
        !(widget.target is DatingReportCard && _category?.priority == 0);
    final notBlocked =
        !_block || sent.blocked
            ? null
            : retryLater
            ? (name.isEmpty
                ? loc.dating_reportNotBlockedNoName
                : loc.dating_reportNotBlocked(name))
            : (name.isEmpty
                ? loc.dating_reportNotBlockedEndedNoName
                : loc.dating_reportNotBlockedEnded(name));
    return [
      Semantics(
        header: true,
        child: Text(
          loc.dating_reportSentTitle,
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: Spacing.sm),
      // M-7: one live region, the not-blocked line in it.
      Semantics(
        liveRegion: true,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(line, style: theme.textTheme.bodyLarge),
            if (notBlocked != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(notBlocked, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      // M-4: the number is a call (S1's confirm first).
      if (number != null) ...[
        const SizedBox(height: Spacing.sm),
        _callButton(loc, number),
      ],
      if (scam) ...[
        const SizedBox(height: Spacing.md),
        Text(loc.dating_reportScam, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Spacing.sm),
        if (_paused)
          DatingCalmLine(loc.dating_pausedLine)
        else if (!_pauseAnswered)
          FlowPrimaryButton(
            key: const ValueKey('dating_report_pause'),
            label: loc.dating_settingsPause,
            busy: _pausing,
            onPressed: _pausing ? null : _pause,
          ),
        if (_pauseFailed)
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
      ],
      const SizedBox(height: Spacing.sm),
      FlowSecondaryButton(
        key: const ValueKey('dating_report_close'),
        label: loc.dating_close,
        onPressed: _close,
      ),
    ];
  }

  /// M-5: "If you're in danger now, call {number}." and the call.
  List<Widget> _danger(AppLocalizations loc, ThemeData theme, String? number) =>
      [
        const SizedBox(height: Spacing.xs),
        Text(
          number == null
              ? loc.dating_reportDangerNoNumber
              : loc.dating_reportDanger(number),
          style: theme.textTheme.bodyMedium,
        ),
        if (number != null) ...[
          const SizedBox(height: Spacing.xs),
          _callButton(loc, number),
        ],
      ];

  Widget _callButton(AppLocalizations loc, String number) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      key: const ValueKey('dating_report_call'),
      // 4.5:1 in both themes (as the W6 threat card's call): onSurface.
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      icon: const Icon(Icons.call_outlined, size: 18),
      onPressed: () => _call(number),
      label: Text(loc.support_call(number)),
    ),
  );

  /// M-4: the W6 threat card's call: S1's confirm, then the dialer.
  Future<void> _call(String phone) async {
    final account = widget.account;
    if (!await showDatingCallSheet(context, account: account, number: phone)) {
      return;
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    await ref.read(supportLauncherProvider)(
      context,
      'tel:${supportDialString(phone)}',
    );
  }

  /// The country's emergency number (S1 W7a), or null for the "your
  /// local emergency number" line (still loading, none, or a failure).
  String? _emergencyNumber() {
    final country = ref.watch(supportCountryProvider).valueOrNull;
    final read = ref.watch(supportResourcesProvider(country));
    if (read.hasError) return null;
    final list = read.valueOrNull?.emergency ?? const <SupportResource>[];
    for (final r in list) {
      if (r.phone case final phone? when phone.trim().isNotEmpty) return phone;
    }
    return null;
  }
}
