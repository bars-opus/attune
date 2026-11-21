// Spec 2 W5c (§3.12, §3.15; carry 16; Task 5 C-1 and I-6 rulings): "Never
// introduce me to these numbers". A country code and a number, and a name
// only the person sees; "Added." whatever the number (it can't be used to
// test whether someone uses Attune). The rows show a name and the last two
// digits, each with Remove; entries kept from before are never shown, only
// counted, and only Leave Dating removes them. Adding works from any phone
// (it only reduces exposure); removing is the server's to check. No field
// lets the keyboard learn what is typed; nothing is kept on the phone.
// Fix round 1: the number is read as the real number it is (C-1), the
// fields hold still while an add is out (I-1), Remove asks first (I-2),
// rows are spoken with a comma (M-3), a quiet wait while the list is read
// and a removed row goes at once (M-4), Dating's own country sheet (M-5),
// and the dial code and number always run left to right (M-6).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/settings/never_introduce_phone.dart';
import 'package:attune/features/dating/settings/never_introduce_sheets.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingNeverIntroduceScreen extends ConsumerStatefulWidget {
  const DatingNeverIntroduceScreen({super.key});

  @override
  ConsumerState<DatingNeverIntroduceScreen> createState() =>
      _DatingNeverIntroduceScreenState();
}

class _DatingNeverIntroduceScreenState
    extends ConsumerState<DatingNeverIntroduceScreen> {
  final _keys = DatingActionKeys();
  final _number = TextEditingController();
  final _label = TextEditingController();
  // Fix 1 (C-1): the account phone's country, not always Ghana.
  late PhoneCountry _country = ref.read(datingNeverCountryProvider);
  bool _adding = false;
  DatingWrite? _added;
  DatingWrite? _removed;
  final _removing = <String>{};

  /// Fix 1 (M-4): removed (the server said ok), hidden before the re-read.
  final _gone = <String>{};

  @override
  void initState() {
    super.initState();
    // D8: the next account sees nothing typed or answered for this one.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _number.clear();
      _label.clear();
      setState(() {
        _country = ref.read(datingNeverCountryProvider);
        _adding = false;
        _added = null;
        _removed = null;
        _removing.clear();
        _gone.clear();
      });
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_adding || _number.text.trim().isEmpty) return;
    final account = ref.read(datingAccountProvider);
    final sentNumber = _number.text;
    final sentLabel = _label.text;
    final sentCountry = _country;
    final label = sentLabel.trim();
    // Fix 1 (C-1): a number written in full keeps its own code; anything
    // else is read for the picked country. Not a real number: the check
    // line, and nothing is sent (a format check, the same for anyone).
    final phone = datingNeverE164(sentNumber, _country);
    if (phone == null) {
      setState(
        () =>
            _added = const DatingWrite(
              ok: false,
              reason: 'invalid',
              field: 'phone',
            ),
      );
      return;
    }
    setState(() {
      _adding = true;
      _added = null;
    });
    final w = await ref
        .read(datingNeverIntroduceGatewayProvider)
        .add(
          _keys.keyFor('add', '$account|$phone|$label'),
          phone,
          label.isEmpty ? null : label,
        );
    _keys.settle('add', reason: w.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // Fix 1 (I-1): the fields are read-only while the add is out; even so,
    // only the text that was sent is cleared, and the answer shows only
    // beside the text it answers.
    // W5 final fix (M-7, T9 N-3): and the country code it was read for.
    final unchanged =
        _number.text == sentNumber &&
        _label.text == sentLabel &&
        _country.isoCode == sentCountry.isoCode;
    if (w.ok) {
      if (_number.text == sentNumber) _number.clear();
      if (_label.text == sentLabel) _label.clear();
      ref.invalidate(datingNeverIntroduceProvider(account));
    }
    setState(() {
      _adding = false;
      _added = unchanged ? w : null;
    });
  }

  Future<void> _remove(DatingNeverIntroduceItem item) async {
    if (!_removing.add(item.id)) return;
    final account = ref.read(datingAccountProvider);
    setState(() => _removed = null);
    // Fix 1 (I-2, owner decision): removing can expose the person again,
    // so it asks first; Keep sends nothing.
    // W5 final fix (M-3): the confirm names the row.
    final sure = await showDatingNeverRemoveSheet(
      context,
      account: account,
      label: item.label,
      digits: item.lastTwo,
    );
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (!sure) {
      setState(() => _removing.remove(item.id));
      return;
    }
    final w = await ref
        .read(datingNeverIntroduceGatewayProvider)
        .remove(item.id);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (w.ok) {
      _gone.add(item.id);
      ref.invalidate(datingNeverIntroduceProvider(account));
    }
    setState(() {
      _removing.remove(item.id);
      _removed = w.ok ? null : w;
    });
  }

  // Fix 1 (M-5): Dating's own sheet (its search never lets the keyboard
  // learn); it closes itself once, so the page never closes with it.
  Future<void> _pickCountry() async {
    // M-7: the code holds still while an add is out, as the fields do.
    if (_adding) return;
    final chosen = await showDatingNeverCountrySheet(
      context,
      account: ref.read(datingAccountProvider),
      selected: _country,
    );
    if (chosen == null || !mounted || _adding) return;
    setState(() {
      _country = chosen;
      _added = null;
    });
  }

  Widget _answer(AppLocalizations loc, DatingWrite w) => switch (w.reason) {
    null => DatingCalmLine(loc.dating_neverAdded),
    'reverify_device' => const DatingReverifyLine(),
    'busy' => DatingCalmLine(loc.dating_busy),
    // Fix 1 (M-2): about every number, never a restriction on the account.
    'feature_unavailable' ||
    'not_eligible' => DatingCalmLine(loc.dating_neverNotNow),
    'rate_limited' => FlowErrorLine(
      text: loc.dating_errorRateLimited,
      liveRegion: true,
    ),
    'limit_reached' => FlowErrorLine(
      text: loc.dating_neverLimit,
      liveRegion: true,
    ),
    'invalid' when w.field == 'label' => FlowErrorLine(
      text: loc.dating_neverCheckLabel,
      liveRegion: true,
    ),
    'invalid' => FlowErrorLine(
      text: loc.dating_neverCheckNumber,
      liveRegion: true,
    ),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final read = ref.watch(datingNeverIntroduceProvider(account));
    final list = read.valueOrNull;
    // A Dating field never lets the keyboard learn or suggest (W3 M-12).
    InputDecoration field(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    return AllowLargeText(
      child: Scaffold(
        // Ruling 5: the title is long, so it wraps as the page's heading
        // (in the bar it would be cut to "Never introduce me to…").
        // Final client fix (C-5): the only page goes back to settings.
        appBar: AppBar(leading: datingRootBackButton(context)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.dating_neverTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (!online) DatingCalmLine(loc.dating_offline),
                Text(loc.dating_neverBody, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Spacing.sm),
                Text(loc.dating_neverCode, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ruling 3: the label replaces the button's own, so the
                    // tap goes on it too (a screen reader can open it).
                    Semantics(
                      button: true,
                      label: loc.dating_neverCountryCode(_country.dialCode),
                      excludeSemantics: true,
                      // M-7: dimmed, and no tap, while an add is out.
                      enabled: !_adding,
                      onTap: _adding ? null : _pickCountry,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(72, 56),
                        ),
                        onPressed: _adding ? null : _pickCountry,
                        // Fix 1 (M-6): "+233", never "233+".
                        child: Text(
                          _country.dialCode,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('dating_never_number'),
                        controller: _number,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        readOnly: _adding,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        decoration: field(loc.dating_neverNumber),
                        // Fix 1 (I-1): "Added." never sits beside a new
                        // number.
                        onChanged: (_) => setState(() => _added = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const ValueKey('dating_never_label'),
                  controller: _label,
                  maxLength: 20,
                  readOnly: _adding,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: field(loc.dating_neverLabel),
                  onChanged: (_) => setState(() => _added = null),
                ),
                FlowPrimaryButton(
                  label: loc.dating_neverAdd,
                  busy: _adding,
                  onPressed:
                      online && _number.text.trim().isNotEmpty ? _add : null,
                ),
                if (_added case final w?) _answer(loc, w),
                const SizedBox(height: Spacing.md),
                // Ruling 4: a read that failed outright says so (offline,
                // the line at the top already says why).
                if (read.hasError && online)
                  FlowErrorLine(
                    text: loc.dating_errorGeneric,
                    liveRegion: true,
                  ),
                // Fix 1 (M-4): a quiet wait while the list is read.
                if (list == null && read.isLoading)
                  Padding(
                    padding: const EdgeInsets.all(Spacing.sm),
                    child: Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: loc.loadingDefaultMessage,
                      ),
                    ),
                  ),
                if (list != null && !list.ok)
                  switch (list.reason) {
                    'reverify_device' => const DatingReverifyLine(),
                    'busy' => DatingCalmLine(loc.dating_busy),
                    _ => FlowErrorLine(
                      text: loc.dating_errorGeneric,
                      liveRegion: true,
                    ),
                  },
                for (final item
                    in list?.items ?? const <DatingNeverIntroduceItem>[])
                  if (!_gone.contains(item.id)) _row(loc, item, online),
                if (_removed case final w?) _answer(loc, w),
                if ((list?.keptCount ?? 0) > 0)
                  DatingCalmLine(
                    loc.dating_neverIntroduceKept(list!.keptCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    AppLocalizations loc,
    DatingNeverIntroduceItem item,
    bool online,
  ) {
    final text =
        item.label == null
            ? loc.dating_neverRowNoLabel(item.lastTwo)
            : loc.dating_neverRow(item.label!, item.lastTwo);
    // Fix 1 (M-3): spoken with a comma (§3.15), never "middle dot".
    final spoken =
        item.label == null
            ? text
            : loc.dating_neverRowSpoken(item.label!, item.lastTwo);
    final canRemove = online && !_removing.contains(item.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(text, semanticsLabel: spoken)),
          Semantics(
            button: true,
            label: loc.dating_neverRemoveLabel(spoken),
            excludeSemantics: true,
            // Ruling 3: read out as dimmed when it can't be used, and
            // usable by a screen reader when it can.
            enabled: canRemove,
            onTap: canRemove ? () => _remove(item) : null,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: canRemove ? () => _remove(item) : null,
              child: Text(loc.dating_neverRemove),
            ),
          ),
        ],
      ),
    );
  }
}
