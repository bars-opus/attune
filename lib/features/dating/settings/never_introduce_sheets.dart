// Spec 2 W5c Task 9 fix round 1: the two sheets "Never introduce me" opens.
// - The country code (M-5): Dating's own picker, whose search field never
//   lets the keyboard learn (sign-in's shared sheet is left as it is). It
//   answers the chosen country and closes once.
// - Remove's confirm (I-2, owner decision): removing is the one change on
//   the screen that can expose the person again, so it asks first. Keep is
//   the safe, first choice; Remove answers once. Either sheet shows nothing
//   of the last account once the signed-in account changes, and closes
//   choosing nothing (D8).
// - W5 final fix: Remove's confirm names the row it removes, "Remove
//   {label}, ending {digits}?" (M-3, T9 N-1); and [showDatingAccountSheet]
//   gives any other Dating sheet the same D8 shape (M-4).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remove's confirm for the row [label] (null: no name) ending [digits],
/// opened as [account]: true when Remove was chosen.
Future<bool> showDatingNeverRemoveSheet(
  BuildContext context, {
  required String? account,
  String? label,
  String digits = '',
}) async =>
    await _show<bool>(
      context,
      'never-remove',
      account,
      false,
      (context, close) =>
          _RemoveSheet(close: close, label: label, digits: digits),
    ) ==
    true;

/// W5 final fix (M-4): a Dating sheet named [name], opened as [account],
/// in the shape of every sheet here: [builder]'s close answers once, and
/// once the signed-in account is no longer [account] the sheet shows
/// nothing of it and closes, choosing nothing (D8).
Future<T?> showDatingAccountSheet<T>(
  BuildContext context, {
  required String name,
  required String? account,
  required Widget Function(BuildContext context, void Function(T?) close)
  builder,
}) => _show<T>(context, name, account, false, builder);

/// Spec 2 W5c Task 10 fix round 1 (M-1): a confirm in Remove's shape (Keep
/// first and filled, the action once; D8), opened as [account]: true when
/// [act] was chosen.
Future<bool> showDatingConfirmSheet(
  BuildContext context, {
  required String? account,
  required String name,
  required String title,
  required String body,
  required String keep,
  required String act,
}) async =>
    await _show<bool>(
      context,
      name,
      account,
      false,
      (context, close) => _ConfirmSheet(
        close: close,
        title: title,
        body: body,
        keep: keep,
        act: act,
      ),
    ) ==
    true;

/// The country-code picker, opened as [account] on [selected]: the chosen
/// country, or null.
Future<PhoneCountry?> showDatingNeverCountrySheet(
  BuildContext context, {
  required String? account,
  required PhoneCountry selected,
}) => _show<PhoneCountry>(
  context,
  'never-country',
  account,
  true,
  (context, close) => _CountrySheet(selected: selected, close: close),
);

Future<T?> _show<T>(
  BuildContext context,
  String name,
  String? account,
  bool tall,
  Widget Function(BuildContext context, void Function(T?) close) builder,
) {
  // Spec 2 W8a round 2 (Re-1-M2): nothing opens once Dating is blank.
  if (datingSheetRefused) return Future<T?>.value();
  return showModalBottomSheet<T>(
    context: context,
    routeSettings: datingSheetSettings(name),
    isScrollControlled: true,
    builder: (sheet) {
      final body = DatingSheetTracker(
        child: AllowLargeText(
          child: _OnceSheet<T>(account: account, builder: builder),
        ),
      );
      return tall
          ? SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.8,
            child: body,
          )
          : body;
    },
  );
}

/// One answer, and D8: [builder]'s close answers once; once the signed-in
/// account is no longer [account] the sheet shows nothing and closes.
class _OnceSheet<T> extends ConsumerStatefulWidget {
  const _OnceSheet({required this.account, required this.builder});

  final String? account;
  final Widget Function(BuildContext context, void Function(T?) close) builder;

  @override
  ConsumerState<_OnceSheet<T>> createState() => _OnceSheetState<T>();
}

class _OnceSheetState<T> extends ConsumerState<_OnceSheet<T>> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(null));
    });
  }

  void _close(T? chosen) {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(chosen);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    return widget.builder(context, _close);
  }
}

class _RemoveSheet extends StatelessWidget {
  const _RemoveSheet({required this.close, this.label, this.digits = ''});

  final void Function(bool?) close;
  final String? label;
  final String digits;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // M-3 (T9 N-1): the row it removes, by its name and last digits, so a
    // wrong tap among several rows is caught here.
    final name = label?.trim() ?? '';
    final title =
        digits.isEmpty
            ? loc.dating_neverRemoveTitle
            : name.isEmpty
            ? loc.dating_neverRemoveTitleNoName(digits)
            : loc.dating_neverRemoveTitleNamed(name, digits);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Spacing.sm),
            Text(loc.dating_neverRemoveBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Spacing.md),
            // Keep is the safe choice: first, and the filled button. Both
            // are at least 48 dp (the flow buttons).
            FlowPrimaryButton(
              label: loc.dating_neverKeep,
              onPressed: () => close(false),
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_neverRemove,
              onPressed: () => close(true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Task 10 fix round 1 (M-1): Remove's layout with its own words.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.close,
    required this.title,
    required this.body,
    required this.keep,
    required this.act,
  });

  final void Function(bool?) close;
  final String title;
  final String body;
  final String keep;
  final String act;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Spacing.sm),
            Text(body, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Spacing.md),
            // Keep is the default: first, and the filled button.
            FlowPrimaryButton(label: keep, onPressed: () => close(false)),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(label: act, onPressed: () => close(true)),
          ],
        ),
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selected, required this.close});

  final PhoneCountry selected;
  final void Function(PhoneCountry?) close;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final countries =
        PhoneCountries.all.where((c) => c.matches(_search.text)).toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                loc.dating_neverCountryTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            // A Dating field never lets the keyboard learn (W3 M-12).
            child: TextField(
              key: const ValueKey('dating_never_country_search'),
              controller: _search,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: loc.dating_neverCountrySearch,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child:
                countries.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Text(loc.dating_neverCountryNone),
                    )
                    : ListView.builder(
                      itemCount: countries.length,
                      itemBuilder: (context, i) {
                        final c = countries[i];
                        final selected = c.isoCode == widget.selected.isoCode;
                        return ListTile(
                          minTileHeight: 48,
                          selected: selected,
                          title: Text('${c.flag} ${c.name}'),
                          trailing: Text(
                            c.dialCode,
                            textDirection: TextDirection.ltr,
                          ),
                          onTap: () => widget.close(c),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
