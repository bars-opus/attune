// Spec 2 W6b (§3.6 Safety cards, §6.1; chat spec §4.1): a card for the
// person who received the message, under it, never for the sender. Its
// words describe the pattern, never the person; the threat card names the
// country's emergency number and the sextortion card its resource (S1 W7a's
// support_resources), or a plain line when there is none. Every card has
// Report (Spec 2 W7a's report sheet), Block and Dismiss; the
// meet-in-private card also has Plan a meet (W6c Task 10's meeting kit).
// Dismissing never weakens later detection. It
// slides in at 150 ms, and not at all under reduce motion.
//
// Fix round 1: only a card that is new to an open chat slides in and is
// read out; one already there when the chat opens, or one that scrolls
// back into view, is shown as it is and never moves the chat (I-1). The
// threat card names a number only when there is one to call, and offers
// to call it (after the S1 confirm, M-2); the sextortion card names its
// resource with a phone, a text number or its address as plain text, and
// without one offers Safety resources (I-2, M-3). Calm colours: the
// theme's surface container with a hairline, never the brand green (M-7).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// §3.15 Chat: cards slide in at 150 ms.
const kDatingCardSlide = Duration(milliseconds: 150);

/// The card's words for [card] (a person with no name is "this person").
String datingCardText(
  AppLocalizations loc,
  DatingSafetyCard card,
  String name,
) {
  final n = name.isEmpty ? loc.dating_cardThisPerson : name;
  final call = card.resource?.callLine;
  final contact = card.resource?.contactLine;
  return switch (card.family) {
    'sexual_pressure' => loc.dating_safetySexualPressure(n),
    'harassment_abuse' => loc.dating_safetyHarassment(n),
    'contact_migration_pressure' => loc.dating_safetyContactMigration,
    'meet_private_pressure' => loc.dating_safetyMeetPrivate,
    'threat_intimidation' =>
      call == null
          ? loc.dating_safetyThreatNoNumber
          : loc.dating_safetyThreat(call),
    'financial_request' => loc.dating_safetyFinancial,
    'sextortion' =>
      contact == null
          ? loc.dating_safetySextortionNoResource
          : loc.dating_safetySextortion(contact),
    'child_access' => loc.dating_safetyChildAccess,
    _ => '',
  };
}

class DatingSafetyCardView extends StatefulWidget {
  const DatingSafetyCardView({
    super.key,
    required this.card,
    required this.name,
    required this.onBlock,
    required this.onDismiss,
    this.onReport,
    this.ended = false,
    this.shown,
    this.onCall,
    this.onResources,
    this.onPlanMeet,
  });

  final DatingSafetyCard card;
  final String name;
  final VoidCallback onBlock;
  final VoidCallback onDismiss;

  /// Spec 2 W7a (§3.6, R-43): the card's Report (null: none offered).
  final VoidCallback? onReport;

  /// The conversation has ended (Block is already done or can't help).
  final bool ended;

  /// Fix round 1 (I-1): the ids of the cards this open chat has shown. A
  /// card already in it is shown as it is (no slide, not read out); one
  /// not yet in it is new: it slides in (not under reduce motion), is read
  /// out, and adds itself. Read each time the card is built, so a card
  /// scrolled back into view finds itself there. Null: new.
  final Set<String>? shown;

  /// M-2: calls [DatingCardResource.phone] (the threat card, with one).
  final ValueChanged<String>? onCall;

  /// M-3: opens Safety resources (the sextortion card without a resource).
  final VoidCallback? onResources;

  /// Spec 2 W6c Task 10 (§3.6): the meet-in-private card's Plan a meet.
  final VoidCallback? onPlanMeet;

  @override
  State<DatingSafetyCardView> createState() => _DatingSafetyCardViewState();
}

class _DatingSafetyCardViewState extends State<DatingSafetyCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kDatingCardSlide,
  );

  /// Made once (a CurvedAnimation listens to its parent until disposed).
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOut,
  );

  /// I-1: whether this card arrived new (fixed for this card's life).
  late final bool _fresh;

  @override
  void initState() {
    super.initState();
    final shown = widget.shown;
    _fresh = shown == null || !shown.contains(widget.card.id);
    shown?.add(widget.card.id);
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
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = datingCardText(loc, widget.card, widget.name);
    final card = widget.card;
    final phone =
        card.family == 'threat_intimidation' ? card.resource?.phone : null;
    final resources =
        card.family == 'sextortion' && card.resource?.contactLine == null;
    final onCall = widget.onCall;
    final onResources = widget.onResources;
    final onPlanMeet =
        card.family == 'meet_private_pressure' && !widget.ended
            ? widget.onPlanMeet
            : null;
    // 4.5:1 on the card in both themes: onSurface, not the theme's green.
    final plain = TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: scheme.onSurface,
    );
    final outlined = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: scheme.outline),
    );
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: -1,
      child: Semantics(
        container: true,
        liveRegion: _fresh,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadiusTokens.mdAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  if (phone != null && onCall != null)
                    OutlinedButton.icon(
                      key: const ValueKey('dating_card_call'),
                      style: outlined,
                      icon: const Icon(Icons.call_outlined, size: 18),
                      onPressed: () => onCall(phone),
                      label: Text(loc.support_call(phone)),
                    ),
                  if (resources && onResources != null)
                    OutlinedButton.icon(
                      key: const ValueKey('dating_card_resources'),
                      style: outlined,
                      icon: const Icon(
                        Icons.health_and_safety_outlined,
                        size: 18,
                      ),
                      onPressed: onResources,
                      label: Text(loc.dating_chatSafetyResources),
                    ),
                  if (onPlanMeet != null)
                    OutlinedButton.icon(
                      key: const ValueKey('dating_card_plan'),
                      style: outlined,
                      icon: const Icon(Icons.event_note_outlined, size: 18),
                      onPressed: onPlanMeet,
                      label: Text(loc.dating_planTitle),
                    ),
                  if (widget.onReport case final onReport?)
                    TextButton(
                      key: const ValueKey('dating_card_report'),
                      style: plain,
                      onPressed: onReport,
                      child: Text(loc.dating_report),
                    ),
                  if (!widget.ended)
                    TextButton(
                      key: const ValueKey('dating_card_block'),
                      style: plain,
                      onPressed: widget.onBlock,
                      child: Text(loc.dating_cardBlock),
                    ),
                  TextButton(
                    key: const ValueKey('dating_card_dismiss'),
                    style: plain,
                    onPressed: widget.onDismiss,
                    child: Text(loc.dating_safetyDismiss),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
