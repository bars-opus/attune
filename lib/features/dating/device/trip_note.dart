// Spec 2 W8b (§2.5, §3.11, §3.15; R-77, R-78; D8): the traveller's note
// and its four choices, only on its own page, /dating/away (Task 7 fix
// round 1, I-2: Me has no capture protection; Me shows a neutral line and
// "What this means" to here). Never a push, never animated. "Keep it hidden"
// and "Show it on this phone anyway" are the person's trip choice: an
// away trip's is the server's (set_dating_trip_choice); a same-gender
// trip's stays on this phone (trip_phone.dart, R-T4-9: never a server
// call). Showing changes only what this phone shows. "Pause Dating" and
// "Set a PIN" mark the note seen (Keep it hidden) and then do what they
// say. The place is named only while this phone's last check said so
// (memory only); otherwise the note says "while you're away". Offline
// every choice waits; busy and failures are calm lines; another account
// on the phone sees nothing of the last one's trip; nothing is done once
// quick exit or sign-out has run (W8a).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart'
    show datingSheetRefused;
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show setDatingLockInDating;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The note's title for [trip].
String datingTripTitle(AppLocalizations loc, DatingTrip trip) =>
    trip.kind == DatingTripKind.away
        ? loc.dating_tripAwayTitle
        : loc.dating_tripSameGenderTitle;

/// The note's words for [trip], naming [country] when it is known.
String datingTripBody(AppLocalizations loc, DatingTrip trip, String? country) {
  final name = country == null ? null : datingCountryName(loc, country);
  return switch ((trip.kind, name)) {
    (DatingTripKind.away, final String n) => loc.dating_tripAwayBody(n),
    (DatingTripKind.away, null) => loc.dating_tripAwayBodyNoPlace,
    (DatingTripKind.sameGender, final String n) => loc
        .dating_tripSameGenderBody(n),
    (DatingTripKind.sameGender, null) => loc.dating_tripSameGenderBodyNoPlace,
  };
}

/// The note and its choices; [onDone] after a choice was taken.
class DatingTripNote extends ConsumerStatefulWidget {
  const DatingTripNote({
    super.key,
    required this.trip,
    required this.country,
    required this.onDone,
    this.paused = false,
  });

  final DatingTrip trip;
  final String? country;
  final VoidCallback onDone;

  /// Final client fix round 2 (server M-1): Dating is paused already, so
  /// "Pause Dating" isn't offered (the other choices still apply: "Show it
  /// on this phone anyway" lifts the hiding for a paused person's reads,
  /// the conversations, too).
  final bool paused;

  @override
  ConsumerState<DatingTripNote> createState() => _DatingTripNoteState();
}

enum _TripAction { hide, show, pause, pin }

class _DatingTripNoteState extends ConsumerState<DatingTripNote> {
  final _keys = DatingActionKeys();
  _TripAction? _busy;
  String? _error;

  /// The account the choice was made for (D8).
  String? _account;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _busy = null;
        _error = null;
      });
    });
  }

  /// The choice itself: the server's for an away trip; this phone's for a
  /// same-gender one (no call, so nothing on the server says it was made).
  Future<DatingWrite> _choose(String account, bool show) async {
    if (widget.trip.kind == DatingTripKind.sameGender) {
      await DatingTripPhone.answer(account, show: show);
      return const DatingWrite(ok: true);
    }
    final choice = await ref
        .read(datingTripGatewayProvider)
        .choose(_keys.keyFor('trip', [account, show]), showHere: show);
    _keys.settle('trip', reason: choice.reason);
    return choice;
  }

  Future<void> _run(_TripAction action) async {
    // W8a: nothing is done under quick exit's decoy.
    if (_busy != null || datingSheetRefused) return;
    final account = ref.read(datingAccountProvider);
    if (account == null) return;
    _account = account;
    setState(() {
      _busy = action;
      _error = null;
    });
    final choice = await _choose(account, action == _TripAction.show);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // No trip any more (it ended, or the flag is off): nothing to choose,
    // and the home says so when read again.
    if (!choice.ok && choice.reason != 'no_trip') {
      setState(() {
        _busy = null;
        _error = choice.reason;
      });
      return;
    }
    if (action == _TripAction.pause) {
      final paused = await ref
          .read(datingLifecycleGatewayProvider)
          .pause(_keys.keyFor('pause', account));
      _keys.settle('pause', error: paused.error);
      if (!mounted || ref.read(datingAccountProvider) != account) return;
      if (!paused.ok) {
        setState(() {
          _busy = null;
          _error =
              paused.error == DatingLifecycleError.busy ? 'busy' : 'failed';
        });
        return;
      }
    }
    if (action == _TripAction.pin) {
      await setDatingLockInDating(context, ref, true);
      if (!mounted || ref.read(datingAccountProvider) != account) return;
    }
    setState(() => _busy = null);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final account = ref.watch(datingAccountProvider);
    final locked = ref.watch(datingLockProvider).valueOrNull ?? false;
    final trip = widget.trip;
    final error = _account == account ? _error : null;
    VoidCallback? act(_TripAction a) =>
        online && _busy == null ? () => _run(a) : null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            datingTripTitle(loc, trip),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          datingTripBody(loc, trip, widget.country),
          key: const ValueKey('dating_trip_body'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (!online) DatingCalmLine(loc.dating_offline),
        if (error == 'busy') DatingCalmLine(loc.dating_busy),
        if (error != null && error != 'busy')
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        FlowPrimaryButton(
          key: const ValueKey('dating_trip_hide'),
          label: loc.dating_tripKeepHidden,
          busy: _busy == _TripAction.hide,
          onPressed: act(_TripAction.hide),
        ),
        if (!trip.showHere) ...[
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_trip_show'),
            label: loc.dating_tripShowAnyway,
            busy: _busy == _TripAction.show,
            onPressed: act(_TripAction.show),
          ),
        ],
        if (!widget.paused) ...[
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_trip_pause'),
            label: loc.dating_tripPause,
            busy: _busy == _TripAction.pause,
            onPressed: act(_TripAction.pause),
          ),
        ],
        if (!locked) ...[
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_trip_pin'),
            label: loc.dating_tripSetPin,
            busy: _busy == _TripAction.pin,
            onPressed: act(_TripAction.pin),
          ),
        ],
      ],
    );
    return content;
  }
}

/// §3.14 /dating/away: the note on its own page, for this account's trip;
/// with no trip (it ended, another account) the gone line.
class DatingAwayScreen extends ConsumerWidget {
  const DatingAwayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    final trip = home.hasError ? null : home.valueOrNull?.trip;
    final Widget body;
    if (home.isLoading && !home.hasValue) {
      body = const SizedBox(height: 96);
    } else if (trip == null) {
      body = DatingCalmLine(loc.dating_cardGone);
    } else {
      body = DatingTripNote(
        key: ValueKey('dating_trip_page_$account'),
        trip: trip,
        country: ref.watch(datingTripPlaceProvider(account)),
        paused: home.valueOrNull?.state == DatingHomeState.paused,
        onDone: () {
          ref.invalidate(datingHomeProvider(account));
          final back = datingRootBackButton(context);
          if (back == null && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
    }
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.flow_slotDatingTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: KeyedSubtree(key: ValueKey(account), child: body),
          ),
        ),
      ),
    );
  }
}
