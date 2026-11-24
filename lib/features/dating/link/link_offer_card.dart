// Spec 2 W9 (§3.9 steps 4 and 6; C-4; Ruling R-W9-3): the Relationship
// home's one Dating card, HomeCard `link_offer` on ConversationsScreen
// (the screen includes it only while [datingPostLinkOfferProvider] reports
// an offer; it lives here, so nothing of Dating is in the chat feature but
// that one entry). For the asker who has not seen it: "You decided
// together." with the one settle, once ([Continue] marks it seen). From 30
// days after linking: "Delete your Dating profile and preferences? You can
// set up Dating again later." [Delete my Dating data] opens Leave Dating
// (§3.8, behind the Dating lock; leaving removes the data the card needs)
// [Keep for now] (never asked again). Each answer is sent once; the card
// goes as soon as it is answered.
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart'
    show DatingLinkMoment;
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// C-4: the card's id in the person's saved order, and its name for a
/// screen reader (the spec's label; the other cards' are English too).
const datingLinkOfferCardId = 'link_offer';
const datingLinkOfferCardLabel = 'Your Dating profile';

/// Whether the Relationship home shows the `link_offer` card now.
bool datingLinkOfferShown(WidgetRef ref) {
  final account = ref.watch(datingAccountProvider);
  final offer = ref.watch(datingPostLinkOfferProvider(account)).valueOrNull;
  return offer != null && offer != DatingPostLinkOffer.none;
}

class DatingLinkOfferCard extends ConsumerStatefulWidget {
  const DatingLinkOfferCard({super.key});

  @override
  ConsumerState<DatingLinkOfferCard> createState() =>
      _DatingLinkOfferCardState();
}

class _DatingLinkOfferCardState extends ConsumerState<DatingLinkOfferCard> {
  bool _sent = false;

  /// Leave Dating was opened from this card and is not known closed; and
  /// whether this screen's route has been covered since.
  bool _leaveOpen = false;
  bool _covered = false;

  /// Fix round 2 (M-2): the last answer wasn't taken (offline or a server
  /// error); a calm line says so and the card stays usable.
  bool _failed = false;

  /// Re-reads the offer, busy until it lands (the old answer stays on
  /// screen while it runs), so a second tap never sends a second answer.
  Future<void> _reread(String? account) async {
    ref.invalidate(datingPostLinkOfferProvider(account));
    try {
      await ref.read(datingPostLinkOfferProvider(account).future);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _sent = false);
  }

  Future<void> _answer(String? account, DatingPostLinkOffer offer) async {
    if (_sent) return;
    setState(() {
      _sent = true;
      _failed = false;
    });
    final ok = await ref.read(datingLinkGatewayProvider).dismiss(offer);
    if (!mounted) return;
    if (!ok) setState(() => _failed = true);
    await _reread(account);
  }

  Future<void> _delete(String? account) async {
    // Fix round 2 (M-1): one Leave at a time, busy until this screen is in
    // front again.
    if (_sent) return;
    setState(() {
      _sent = true;
      _failed = false;
      _leaveOpen = true;
      _covered = false;
    });
    await context.push(DatingPaths.leave);
    // A pop came back before this screen's route said so (or there is no
    // route to watch).
    if (!mounted || !_leaveOpen) return;
    _leaveOpen = false;
    await _reread(account);
  }

  /// Ruling 2 (Task 6, R-W9-8), fix round 2: the offer is read again when
  /// this screen is in front again after Leave, however Leave ended. Its
  /// Done (after leaving or pausing) and the Dating lock's Back go home with
  /// context.go, which never completes the push.
  void _watchReturn(String? account) {
    if (!_leaveOpen) return;
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (!current) {
      _covered = true;
    } else if (_covered) {
      _leaveOpen = false;
      _covered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reread(account));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    final offer = ref.watch(datingPostLinkOfferProvider(account)).valueOrNull;
    _watchReturn(account);
    // Fix round 2 (M-2): offline, the answers wait (Leave never does, R-48).
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final canAnswer = online && !_sent;
    final Widget? line =
        !online
            ? DatingCalmLine(loc.dating_linkOffline)
            : _failed
            ? DatingCalmLine(loc.dating_errorGeneric)
            : null;
    final Widget content;
    switch (offer) {
      case DatingPostLinkOffer.linked:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DatingLinkMoment(
              body: loc.dating_linkDecidedBody,
              onContinue:
                  canAnswer
                      ? () => _answer(account, DatingPostLinkOffer.linked)
                      : null,
            ),
            if (line != null) line,
          ],
        );
      case DatingPostLinkOffer.delete:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                loc.dating_linkOfferTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              loc.dating_linkOfferBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (line != null) line,
            const SizedBox(height: Spacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                TextButton(
                  key: const ValueKey('dating_link_offer_keep'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  onPressed:
                      canAnswer
                          ? () => _answer(account, DatingPostLinkOffer.delete)
                          : null,
                  child: Text(loc.dating_linkOfferKeep),
                ),
                FilledButton.tonal(
                  key: const ValueKey('dating_link_offer_delete'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _sent ? null : () => unawaited(_delete(account)),
                  child: Text(loc.dating_linkOfferDelete),
                ),
              ],
            ),
          ],
        );
      case DatingPostLinkOffer.none || null:
        return const SizedBox.shrink();
    }
    return CardInkWell(
      borderRadius: BorderRadiusTokens.floatingNavAll,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: KeyedSubtree(
          key: ValueKey('dating_link_offer_$account'),
          child: content,
        ),
      ),
    );
  }
}
