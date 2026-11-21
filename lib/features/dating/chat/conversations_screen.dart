// Spec 2 W6a (§3.5 the conversations list, §3.15): each row the other
// person's first name and age, the last message as this person reads it
// (hidden spans "•••"), and a dot (never a count) for something new; the
// conversations that ended in the last 30 days below. A standard list,
// read again on a chat signal and on the way back from a chat. D8: one
// entry per account; memory only.
//
// Final client fix wave: it reads again when the connection comes back
// (I-1); covered by a chat, it waits for the way back, which reads it
// anyway (M-8).
//
// Owner follow-up (fallback poll): while the signal channel is not joined
// (some networks block WebSockets), the list reads again on the signals'
// slow poll, only while it is the page shown and no read is on its way,
// and never for another account; the connection's return does not read
// again when a rejoin already has (N-1).
//
// Poll fix round 1 (poll-review.md): a background read that fails or is
// busy keeps the last good list, under a line that is never read out
// unless Try again asked for it; only a first load shows the refusal
// (I-1). The list reads again on resume (M-2), and each of its own reads
// pushes the next poll a full wait out (M-3).
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingConversationsScreen extends ConsumerStatefulWidget {
  const DatingConversationsScreen({super.key});

  @override
  ConsumerState<DatingConversationsScreen> createState() =>
      _DatingConversationsScreenState();
}

class _DatingConversationsScreenState
    extends ConsumerState<DatingConversationsScreen>
    with WidgetsBindingObserver {
  /// I-1: the last good list and the account it is for (D8: another
  /// account never sees it; memory only).
  DatingConversations? _kept;
  String? _keptFor;

  /// I-1: Try again asked for the read on its way, so its answer may be
  /// read out; a read the person didn't ask for never is.
  bool _asked = false;

  /// M-8: the list's route (a read only while it is the page shown).
  ModalRoute<Object?>? _route;

  bool get _shown => mounted && (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// M-2: realtime never replays what changed while the app was away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _shown) {
      _reread(ref.read(datingAccountProvider));
    }
  }

  /// The list read again: [asked] when the person tapped Try again. M-3:
  /// the next poll waits a full interval from here.
  void _reread(String? account, {bool asked = false}) {
    if (!mounted) return;
    _asked = asked;
    if (account != null && ref.exists(datingChatSignalsProvider(account))) {
      ref.read(datingChatSignalsProvider(account).notifier).readStarted();
    }
    ref.invalidate(datingConversationsProvider(account));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    // M-8: only while the list is the page shown (the way back from a chat
    // reads it again).
    _route = ModalRoute.of(context);
    bool shown() => _shown;
    ref.listen(datingChatSignalsProvider(account), (previous, next) {
      final again =
          next.reads != previous?.reads ||
          (next.polls != previous?.polls &&
              !ref.read(datingConversationsProvider(account)).isLoading);
      if (again && shown() && account == ref.read(datingAccountProvider)) {
        _reread(account);
      }
    });
    // I-1: realtime never replays what changed while the connection was
    // down: its return reads again.
    ref.listen<AsyncValue<bool>>(datingOnlineProvider, (previous, next) {
      // N-1: a rejoin since the phone went offline has already read again.
      if (ref.read(datingChatSignalsProvider(account)).rejoined) return;
      if (previous?.valueOrNull == false &&
          next.valueOrNull == true &&
          shown()) {
        _reread(account);
      }
    });
    final read = ref.watch(datingConversationsProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    // I-1: the last good list, for this account only.
    if (_keptFor != account) {
      _kept = null;
      _keptFor = account;
    }
    final now = read.valueOrNull;
    if (now != null && now.ok) _kept = now;
    final kept = _kept;
    // Fix round 1: never after the list has gone (a read on the way back).
    void reread() => _reread(account);
    void retry() => _reread(account, asked: true);

    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          // Fix round 1 (I-3): the only page goes back to Me.
          leading: datingRootBackButton(context),
          title: Text(loc.dating_chatsTitle),
        ),
        body: SafeArea(
          child: switch (read) {
            AsyncData(value: final d) when d.ok => _list(
              context,
              loc,
              d,
              reread,
            ),
            // I-1: a background read refused: the list stays.
            AsyncData(value: final d) when kept != null => _list(
              context,
              loc,
              kept,
              reread,
              line: _keptLine(context, loc, d.reason, online, retry),
            ),
            AsyncError() when kept != null => _list(
              context,
              loc,
              kept,
              reread,
              line: _keptLine(context, loc, 'failed', online, retry),
            ),
            AsyncData(value: final d) => ListView(
              padding: AppContentWidth.padded(
                context,
                const EdgeInsets.all(Spacing.md),
              ),
              children: [_refusal(loc, d.reason, online, retry)],
            ),
            AsyncError() => ListView(
              padding: AppContentWidth.padded(
                context,
                const EdgeInsets.all(Spacing.md),
              ),
              children: [_refusal(loc, 'failed', online, retry)],
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _refusal(
    AppLocalizations loc,
    String? reason,
    bool online,
    VoidCallback reread,
  ) {
    final retry = FlowSecondaryButton(
      label: loc.dating_tryAgain,
      onPressed: reread,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (reason) {
        _ when !online => [DatingCalmLine(loc.dating_offline), retry],
        'reverify_device' => [const DatingReverifyLine()],
        'busy' => [DatingCalmLine(loc.dating_busy), retry],
        _ => [
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          retry,
        ],
      },
    );
  }

  /// I-1: why the list shown is the last good one, read out only when Try
  /// again asked (reverify_device keeps its own line: it needs the
  /// person, as in the chat).
  Widget _keptLine(
    BuildContext context,
    AppLocalizations loc,
    String? reason,
    bool online,
    VoidCallback retry,
  ) {
    final text =
        !online
            ? loc.dating_offline
            : reason == 'busy'
            ? loc.dating_busy
            : loc.dating_errorGeneric;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.sm,
        Spacing.md,
        0,
      ),
      child:
          online && reason == 'reverify_device'
              ? const DatingReverifyLine()
              : Semantics(
                container: true,
                liveRegion: _asked,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Spacing.sm,
                  children: [
                    Text(text, style: Theme.of(context).textTheme.bodyMedium),
                    FlowTextLink(label: loc.dating_tryAgain, onPressed: retry),
                  ],
                ),
              ),
    );
  }

  String _spoken(AppLocalizations loc, String text) =>
      [
        for (final (part, masked) in datingMaskedParts(text))
          masked ? ' ${loc.dating_chatMaskedLabel} ' : part,
      ].join().replaceAll(RegExp(' {2,}'), ' ').trim();

  Widget _list(
    BuildContext context,
    AppLocalizations loc,
    DatingConversations d,
    VoidCallback reread, {
    Widget? line,
  }) {
    final theme = Theme.of(context);
    void open(String matchId) =>
        unawaited(context.push(DatingPaths.chat(matchId)).whenComplete(reread));
    String named(String name, int? age) =>
        name.isEmpty
            ? loc.dating_chatTitleNoName
            : age == null
            ? name
            : loc.dating_chatTitle(name, age);
    // Fix round 1 (M-14): on an iPad, the rows sit in the list column.
    return ListView(
      padding: AppContentWidth.padded(
        context,
        const EdgeInsets.symmetric(vertical: Spacing.sm),
      ),
      children: [
        if (line != null) line,
        if (d.conversations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              loc.dating_chatsEmpty,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        for (final c in d.conversations)
          Builder(
            builder: (context) {
              final title = named(c.displayName, c.age);
              final last = c.last;
              // Task 9 fix round 2: Close kindly's message in the app's
              // words, as in the chat (never the server's English copy).
              final text =
                  last?.kind == 'close_kindly'
                      ? loc.dating_closeKindlyMessage
                      : last?.text ?? '';
              final preview =
                  last == null
                      ? loc.dating_chatsNoMessage
                      : last.mine
                      ? loc.dating_chatsYouSaid(text)
                      : text;
              final spoken = [
                title,
                last == null
                    ? loc.dating_chatsNoMessage
                    : last.mine
                    ? loc.dating_chatsYouSaid(_spoken(loc, text))
                    : _spoken(loc, text),
                if (c.isNew) loc.dating_chatsNew,
              ].join(', ');
              return Semantics(
                button: true,
                label: spoken,
                excludeSemantics: true,
                onTap: () => open(c.matchId),
                child: ListTile(
                  key: ValueKey('dating_chats_row_${c.matchId}'),
                  minVerticalPadding: Spacing.sm,
                  title: Text(title),
                  subtitle: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing:
                      c.isNew
                          ? Container(
                            key: const ValueKey('dating_chats_dot'),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                          : null,
                  onTap: () => open(c.matchId),
                ),
              );
            },
          ),
        if (d.ended.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.lg,
              Spacing.md,
              Spacing.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                loc.dating_chatsEnded,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          for (final e in d.ended)
            Semantics(
              container: true,
              child: ListTile(
                key: ValueKey('dating_chats_ended_${e.matchId}'),
                title: Text(
                  e.displayName.isEmpty
                      ? loc.dating_chatTitleNoName
                      : e.displayName,
                ),
                subtitle: Text(loc.dating_chatEnded),
              ),
            ),
        ],
      ],
    );
  }
}
