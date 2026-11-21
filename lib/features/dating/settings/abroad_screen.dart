// Spec 2 W5c (§2.6, §3.12, §3.15): Other countries. Each open country the
// person may join, with its switch. Turning one on shows the cross-border
// card first (the scam warning and who is introduced across borders) and
// writes only on "Turn on for {country}"; turning one off writes at once
// (it only narrows who sees the person, never refused). Until the person is
// verified and 14 days in, the switches can only go off. Standard list,
// no motion; every answer is fixed copy.
//
// Task 10 fix round 1: the switches wait for a fresh read after every save,
// and a write is built from the read as it is when sent, never the list
// the tap saw (I-1); on a phone Dating doesn't trust, the page shows no
// list, only the re-verify line and "Turn off every other country", which
// the server takes on any phone (M-1); the rows use countryNameFor (M-3).
//
// W5 final fix: the cross-border card is a D8 sheet (M-4); the wait line
// goes once the read lands (M-8, T10 N-1); "Done." follows only "Turn off
// every other country" (M-9, T10 N-2); and a person who isn't eligible
// (any more) gets the same off-only path as an untrusted phone, never the
// list, which would tell whoever holds the phone whether the profile is a
// man-woman one (M-11).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/settings/never_introduce_sheets.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingAbroadScreen extends ConsumerStatefulWidget {
  const DatingAbroadScreen({super.key});

  @override
  ConsumerState<DatingAbroadScreen> createState() => _DatingAbroadScreenState();
}

class _DatingAbroadScreenState extends ConsumerState<DatingAbroadScreen> {
  final _keys = DatingActionKeys();
  bool _saving = false;
  DatingWrite? _answer;

  /// M-1: "Turn off every other country" was answered ok.
  bool _clearedAll = false;

  /// W5 final fix (M-8): a tap that came while the list was being read
  /// again; said calmly until that read lands.
  bool _waited = false;

  @override
  void initState() {
    super.initState();
    // D8: the next account sees nothing of this one's answers.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _saving = false;
        _answer = null;
        _clearedAll = false;
        _waited = false;
      });
    });
  }

  /// W5 final fix (M-4): the card is opened as [account] and, once another
  /// account signs in, shows nothing of this one (no country) and closes
  /// choosing nothing (D8), as every other Dating sheet does.
  Future<bool> _card(String code, String? account) async {
    final loc = AppLocalizations.of(context)!;
    // Ruling A: the sentence form ("the United Kingdom"), as every Dating
    // sentence names a country.
    final name = datingCountryName(loc, code);
    final yes = await showDatingAccountSheet<bool>(
      context,
      name: 'abroad-card',
      account: account,
      builder:
          (sheet, close) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // M-4: the card's heading, as every Dating sheet has.
                  Semantics(
                    header: true,
                    child: Text(
                      loc.dating_abroadTitle,
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    loc.dating_abroadCard,
                    style: Theme.of(sheet).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Spacing.md),
                  FlowPrimaryButton(
                    label: loc.dating_abroadTurnOn(name),
                    onPressed: () => close(true),
                  ),
                  const SizedBox(height: Spacing.sm),
                  FlowSecondaryButton(
                    label: loc.dating_abroadNotNow,
                    onPressed: () => close(false),
                  ),
                ],
              ),
            ),
          ),
    );
    return yes ?? false;
  }

  Future<void> _toggle(String code, bool on) async {
    if (_saving) return;
    // Ruling B (D8): the account is the one whose list was shown; a card
    // answered after another account signed in writes nothing.
    final account = ref.read(datingAccountProvider);
    if (on && !await _card(code, account)) return;
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // Fix round 1 (I-1): the list as the read has it now (the card may
    // have been open across a re-read), never the one the tap saw; while
    // a read is under way nothing is sent.
    final now = ref.read(datingAbroadProvider(account));
    final current = now.valueOrNull;
    if (now.isLoading) {
      // Said calmly: the switches come back once the read lands (and,
      // M-8, so does the line: it goes when the read does).
      setState(() {
        _answer = null;
        _waited = true;
      });
      return;
    }
    if (current == null || !current.ok || (on && !current.eligible)) return;
    final list = [...current.on.where((c) => c != code), if (on) code]..sort();
    await _write(account, list);
  }

  /// M-1: on a phone Dating doesn't trust, every other country off (the
  /// server narrows on any phone), after a confirm whose default is Keep.
  /// W5 final fix (M-11): the same for a person who isn't eligible, with
  /// [body] saying when a country can go on again.
  Future<void> _clearAll(String body) async {
    if (_saving) return;
    final loc = AppLocalizations.of(context)!;
    final account = ref.read(datingAccountProvider);
    final yes = await showDatingConfirmSheet(
      context,
      account: account,
      name: 'abroad-all-off',
      title: loc.dating_abroadAllOffTitle,
      body: body,
      keep: loc.dating_abroadAllOffKeep,
      act: loc.dating_abroadAllOffConfirm,
    );
    if (!yes || !mounted || ref.read(datingAccountProvider) != account) {
      return;
    }
    final w = await _write(account, const []);
    // M-9 (T10 N-2): "Done." follows this action only, never a last
    // switch turned off on the list.
    if (w != null && w.ok && mounted) setState(() => _clearedAll = true);
  }

  /// The answer, or null when it no longer belongs on this page (closed,
  /// or another account signed in).
  Future<DatingWrite?> _write(String? account, List<String> list) async {
    setState(() {
      _saving = true;
      _answer = null;
      _waited = false;
    });
    final w = await ref
        .read(datingAbroadGatewayProvider)
        .set(_keys.keyFor('abroad', '$account|$list'), list);
    _keys.settle('abroad', reason: w.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return null;
    ref.invalidate(datingAbroadProvider(account));
    setState(() {
      _saving = false;
      _answer = w.ok ? null : w;
    });
    return w;
  }

  /// M-1 and W5 final fix (M-11): the one action the page offers where it
  /// shows no list; then "Done.", the same whatever was on.
  List<Widget> _allOff(AppLocalizations loc, bool online, String body) => [
    if (_clearedAll)
      DatingCalmLine(loc.dating_abroadAllOffDone)
    else ...[
      const SizedBox(height: Spacing.md),
      FlowSecondaryButton(
        label: loc.dating_abroadAllOff,
        onPressed: online && !_saving ? () => _clearAll(body) : null,
      ),
    ],
  ];

  Widget _line(AppLocalizations loc, String? reason) => switch (reason) {
    'reverify_device' => const DatingReverifyLine(),
    'busy' => DatingCalmLine(loc.dating_busy),
    'not_yet' => DatingCalmLine(loc.dating_abroadDisabled),
    'not_available' => DatingCalmLine(loc.dating_notAvailableHere),
    'not_eligible' => DatingCalmLine(loc.dating_sectionUnavailable),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final read = ref.watch(datingAbroadProvider(account));
    // M-8 (T10 N-1): the wait line goes when the read it waited for lands.
    ref.listen<AsyncValue<DatingAbroadOptions>>(datingAbroadProvider(account), (
      _,
      next,
    ) {
      if (_waited && !next.isLoading) setState(() => _waited = false);
    });
    final o = read.valueOrNull;
    // I-1: a switch waits for the fresh read after a save.
    final fresh = !read.isLoading;
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          // Final client fix (C-5): the only page goes back to settings.
          leading: datingRootBackButton(context),
          title: Text(loc.dating_abroadTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!online) DatingCalmLine(loc.dating_offline),
                // Ruling C: the wait is spoken (Task 9 fix round 1, M-4).
                if (o == null)
                  Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: loc.loadingDefaultMessage,
                    ),
                  )
                else if (o.reason == 'reverify_device') ...[
                  // M-1: no list and nothing of any country here.
                  const DatingReverifyLine(),
                  ..._allOff(loc, online, loc.dating_abroadAllOffBody),
                ] else if (!o.ok)
                  _line(loc, o.reason)
                // W5 final fix (M-11): not eligible (or no longer), the
                // person can still turn every country off, and sees no
                // list and no country.
                else if (!o.eligible) ...[
                  DatingCalmLine(loc.dating_abroadDisabled),
                  ..._allOff(loc, online, loc.dating_abroadAllOffBodyNotYet),
                ] else ...[
                  if (o.countries.isEmpty)
                    DatingCalmLine(loc.dating_abroadNone),
                  for (final (code, on) in o.countries)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(countryNameFor(code)),
                      value: on,
                      // Off is always allowed; on needs the person eligible.
                      onChanged:
                          online && !_saving && fresh && (on || o.eligible)
                              ? (v) => _toggle(code, v)
                              : null,
                    ),
                ],
                if (_waited) DatingCalmLine(loc.dating_busy),
                if (_answer case final w?) _line(loc, w.reason),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
