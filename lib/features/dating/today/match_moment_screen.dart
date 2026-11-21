// Spec 2 W5b (§3.5, §3.15 Match moment): shown once to each person, the
// next time they open Today. "You and {Name} are both interested." The two
// first-letter avatars settle together once (at most 600 ms, one light
// haptic); with reduce motion they fade in. No counter, no burst, no "It's
// a match". The moment is marked seen when it shows (best effort). "Say
// hello" opens the conversation once W6a's chat exists (Ruling R-11).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.5: the settle, at most 600 ms, once.
const kDatingMomentSettle = Duration(milliseconds: 600);

/// W6a flips this when /dating/chat/:matchId exists (Ruling R-11).
const kDatingChatReady = true;

class DatingMatchMomentScreen extends ConsumerStatefulWidget {
  const DatingMatchMomentScreen({
    super.key,
    required this.matchId,
    this.moment,
    this.myName,
    this.account,
  });

  final String matchId;

  /// From Today (memory only); a link without it reads Today again.
  final DatingMoment? moment;
  final String? myName;

  /// T7 fix 1 (M-1, D8): the account Today read [moment] for. Another
  /// account (or none) never sees it: the screen reads that account's own
  /// Today instead.
  final String? account;

  @override
  ConsumerState<DatingMatchMomentScreen> createState() =>
      _DatingMatchMomentScreenState();
}

class _DatingMatchMomentScreenState
    extends ConsumerState<DatingMatchMomentScreen>
    with SingleTickerProviderStateMixin {
  // Made in initState: a lazy one would be first made in dispose.
  late final AnimationController _settle;
  bool _marked = false;
  bool _played = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: kDatingMomentSettle);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _shown(DatingMoment m) {
    if (!_marked) {
      _marked = true;
      ref.read(datingTodayGatewayProvider).momentSeen(m.matchId);
    }
    if (_played) return;
    _played = true;
    final reduce = MediaQuery.of(context).disableAnimations;
    _settle.duration =
        reduce ? const Duration(milliseconds: 150) : kDatingMomentSettle;
    _settle.forward();
    if (!reduce) HapticFeedback.lightImpact();
  }

  void _later() =>
      context.canPop() ? context.pop() : context.go(DatingPaths.today);

  /// T7 fix 1 (M-2): a link (or a return through the unlock, which drops
  /// the moment) whose moment Today no longer lists goes to Today, never a
  /// blank page.
  void _toToday() {
    if (_left) return;
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(DatingPaths.today);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    // T7 fix 1 (M-1): the moment Today handed over is this account's only.
    final mine = widget.account != null && widget.account == account;
    var moment = mine ? widget.moment : null;
    var myName = mine ? widget.myName : null;
    var waiting = false;
    if (moment == null) {
      final read = ref.watch(datingTodayProvider(account));
      final day = read.valueOrNull;
      for (final m in day?.moments ?? const <DatingMoment>[]) {
        if (m.matchId == widget.matchId) moment = m;
      }
      myName ??= day?.myName;
      waiting = !read.hasValue && !read.hasError;
      if (moment == null && !waiting) _toToday();
    }
    final m = moment;
    if (m != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _shown(m) : null,
      );
    }
    final theme = Theme.of(context);
    final reduce = MediaQuery.of(context).disableAnimations;
    Widget avatar(String name, double side) => AnimatedBuilder(
      animation: _settle,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_settle.value);
        return reduce
            ? Opacity(opacity: t, child: child)
            : Transform.translate(
              offset: Offset(side * 24 * (1 - t), 0),
              child: child,
            );
      },
      child: CircleAvatar(
        radius: 32,
        backgroundColor: theme.colorScheme.primaryContainer,
        // T7 fix 1 (M-8): no name, a person's outline (never a blank disc).
        child:
            name.trim().isEmpty
                ? Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.onPrimaryContainer,
                )
                : Text(
                  name.trim().characters.first.toUpperCase(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
      ),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          child:
              m == null
                  // T7 fix 1 (M-2): reading, or on the way to Today.
                  ? (waiting
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink())
                  : SingleChildScrollView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ExcludeSemantics(
                          child: Row(
                            key: const ValueKey('dating_moment_avatars'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              avatar(myName ?? '', -1),
                              const SizedBox(width: Spacing.sm),
                              avatar(m.name, 1),
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.lg),
                        Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            // T7 fix 1 (M-8): never "You and  are".
                            m.name.trim().isEmpty
                                ? loc.dating_momentTitleNoName
                                : loc.dating_momentTitle(m.name.trim()),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          loc.dating_momentBody,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: Spacing.lg),
                        if (kDatingChatReady) ...[
                          FlowPrimaryButton(
                            label: loc.dating_momentSayHello,
                            // Spec 2 W6a: the chat, in the moment's place.
                            onPressed:
                                () => context.pushReplacement(
                                  DatingPaths.chat(m.matchId),
                                ),
                          ),
                          const SizedBox(height: Spacing.sm),
                        ],
                        FlowSecondaryButton(
                          label: loc.dating_momentLater,
                          onPressed: _later,
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}
