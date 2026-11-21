// Spec 2 W6c (§3.6 Check-in, Get help; §3.13): where the neutral
// "A quick check-in from Attune." push opens (behind the Dating lock).
// "How did it go?" [I'm OK] [Get help] [We met] [Not now]. Get help asks
// first ("Show emergency numbers?"), then opens the country's support
// directory (S1 W7a, emergency first, with S1's own call confirm), and
// offers a text the person sends themselves: "I need help. I'm at
// {place}. Please call me." Nothing is ever sent automatically. Nothing
// here moves.
//
// Task 10 rulings: Get help's confirm is a Dating sheet with the D8
// account guard (another account closes it, choosing nothing); another
// account also hides Message someone you trust again, and never reads the
// last account's place.
//
// Fix round 1 (I-6): Message someone you trust is offered as soon as Get
// help is tapped, on the confirm itself and under Get help whatever the
// person chose there (Show, Cancel), so there is more help and never
// less; a text that can't open says so (I-5). M-7: the title is read once
// (the heading; the app bar's copy is visual only).
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/chat/chat_sheets.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingCheckinScreen extends ConsumerStatefulWidget {
  const DatingCheckinScreen({super.key});

  @override
  ConsumerState<DatingCheckinScreen> createState() =>
      _DatingCheckinScreenState();
}

class _DatingCheckinScreenState extends ConsumerState<DatingCheckinScreen> {
  bool _help = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _help = false;
        _failed = false;
      });
    });
  }

  void _leave() =>
      context.canPop() ? context.pop() : context.go(RouteNames.home);

  /// The text the person sends themselves: the plan's place when this
  /// account has one in memory, never another account's.
  String _helpText(AppLocalizations loc) {
    final account = ref.read(datingAccountProvider);
    final place =
        DatingPlanMemory.account == account ? DatingPlanMemory.place : null;
    return place == null
        ? loc.dating_checkinHelpTextNoPlace
        : loc.dating_checkinHelpText(place);
  }

  Future<void> _message(Rect? origin) async {
    final loc = AppLocalizations.of(context)!;
    try {
      await ref.read(datingSmsProvider)(_helpText(loc), origin);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _getHelp(BuildContext button) async {
    final origin = datingOriginOf(button);
    final account = ref.read(datingAccountProvider);
    // I-6: the silent text is there from now on, whatever is chosen.
    setState(() => _help = true);
    final choice = await showDatingCheckinHelpSheet(context, account: account);
    if (choice == null || !mounted) return;
    if (ref.read(datingAccountProvider) != account) return;
    switch (choice) {
      case DatingCheckinHelpChoice.show:
        unawaited(context.push(RouteNames.safetyResources));
      case DatingCheckinHelpChoice.message:
        await _message(origin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    ref.watch(datingAccountProvider);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: ExcludeSemantics(child: Text(loc.dating_checkinTitle)),
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
                  header: true,
                  child: Text(
                    loc.dating_checkinTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                FlowPrimaryButton(
                  key: const ValueKey('dating_checkin_ok'),
                  label: loc.dating_checkinOk,
                  onPressed: _leave,
                ),
                const SizedBox(height: Spacing.sm),
                Builder(
                  builder:
                      (button) => FlowSecondaryButton(
                        key: const ValueKey('dating_checkin_help'),
                        label: loc.dating_checkinHelp,
                        onPressed: () => unawaited(_getHelp(button)),
                      ),
                ),
                if (_help) ...[
                  const SizedBox(height: Spacing.sm),
                  Builder(
                    builder:
                        (button) => FlowSecondaryButton(
                          key: const ValueKey('dating_checkin_message'),
                          label: loc.dating_checkinMessageSomeone,
                          onPressed:
                              () => unawaited(_message(datingOriginOf(button))),
                        ),
                  ),
                  if (_failed) DatingCalmLine(loc.dating_errorGeneric),
                ],
                const SizedBox(height: Spacing.sm),
                // We met names no match here (the push carries none): the
                // conversations, where each chat's Safety sheet says it.
                FlowSecondaryButton(
                  key: const ValueKey('dating_checkin_we_met'),
                  label: loc.dating_weMet,
                  onPressed: () => context.go(DatingPaths.chats),
                ),
                const SizedBox(height: Spacing.sm),
                FlowTextLink(
                  label: loc.dating_checkinNotNow,
                  onPressed: _leave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
