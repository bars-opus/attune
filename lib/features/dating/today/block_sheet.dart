// Spec 2 W5b Task 7b (§3.4 the card's "More", §3.6 Block; D8; Ruling
// R-36): the card's overflow and the Block confirm. The overflow offers
// Block (W7a adds Report). The confirm names the person, says the person
// won't be told and won't be introduced again, and answers once: a second
// tap does nothing. Offline, Block waits (nothing is queued). Either sheet
// shows nothing of the last account once the signed-in account changes,
// and closes choosing nothing. Today sends the block.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The overflow on [name]'s card, opened as [account]: true when Block was
/// chosen.
Future<bool> showDatingCardMoreSheet(
  BuildContext context, {
  required String? account,
  required String name,
}) => _show(
  context,
  'card-more',
  account,
  (context, close) => _MoreSheet(name: name, close: close),
);

/// §3.6 Block's confirm for [name], opened as [account]: true when the
/// person chose Block.
Future<bool> showDatingBlockSheet(
  BuildContext context, {
  required String? account,
  required String name,
}) => _show(
  context,
  'block',
  account,
  (context, close) => _BlockSheet(name: name, close: close),
);

Future<bool> _show(
  BuildContext context,
  String name,
  String? account,
  Widget Function(BuildContext context, void Function(bool) close) builder,
) async {
  final chosen = await showModalBottomSheet<bool>(
    context: context,
    routeSettings: datingSheetSettings(name),
    isScrollControlled: true,
    builder:
        (sheet) => DatingSheetTracker(
          child: AllowLargeText(
            child: _OnceSheet(account: account, builder: builder),
          ),
        ),
  );
  return chosen == true;
}

/// One answer, and D8: [builder]'s close answers once (a second tap does
/// nothing); once the signed-in account is no longer [account] the sheet
/// shows nothing and closes, choosing nothing.
class _OnceSheet extends ConsumerStatefulWidget {
  const _OnceSheet({required this.account, required this.builder});

  final String? account;
  final Widget Function(BuildContext context, void Function(bool) close)
  builder;

  @override
  ConsumerState<_OnceSheet> createState() => _OnceSheetState();
}

class _OnceSheetState extends ConsumerState<_OnceSheet> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(false));
    });
  }

  void _close(bool chosen) {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(chosen);
    } else {
      // Under another route: removed (its answer never comes, so nothing
      // is sent).
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

/// T7b fix 1 (M-1): "Block {name}", or "Block this person" with no name.
String _row(AppLocalizations loc, String name) =>
    name.isEmpty ? loc.dating_blockRowNoName : loc.dating_blockRow(name);

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.name, required this.close});

  final String name;
  final void Function(bool) close;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                loc.dating_cardMore,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            InfoRowWidget(
              title: _row(loc, name),
              subtitle: '',
              icon: Icons.block,
              showAvatar: false,
              // T7b fix 1 (M-6): Block stays here; no "open in new" icon.
              disableTrailing: true,
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              onTap: () => close(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockSheet extends ConsumerWidget {
  const _BlockSheet({required this.name, required this.close});

  final String name;
  final void Function(bool) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    void block() => close(true);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                name.isEmpty
                    ? loc.dating_blockTitleNoName
                    : loc.dating_blockTitle(name),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              name.isEmpty
                  ? loc.dating_blockBodyNoName
                  : loc.dating_blockBody(name),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: Spacing.md),
            if (!online) DatingCalmLine(loc.dating_offline),
            // At least 48 dp (FlowPrimaryButton); read as "Block {name}".
            Semantics(
              label: _row(loc, name),
              button: true,
              enabled: online,
              excludeSemantics: true,
              onTap: online ? block : null,
              child: FlowPrimaryButton(
                label: loc.dating_cardBlock,
                onPressed: online ? block : null,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_blockCancel,
              onPressed: () => close(false),
            ),
          ],
        ),
      ),
    );
  }
}
