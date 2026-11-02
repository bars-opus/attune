import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/me/data/me_device_store.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The Dating slot at the top of Me, Dating path only (Spec 1 §3.9).
/// It calls no Dating RPC (review I-4): it reads the home state's
/// `dating {enabled, enrolled}` and `link`, and the D15 open-country list.
/// Spec 2 W3 replaces it with DatingSection. While the Dating lock is on it
/// is one row until the Safety PIN is entered.
class DatingSlot extends ConsumerStatefulWidget {
  const DatingSlot({super.key, required this.home});

  final HomeSnapshot home;

  @override
  ConsumerState<DatingSlot> createState() => _DatingSlotState();
}

class _DatingSlotState extends ConsumerState<DatingSlot>
    with WidgetsBindingObserver {
  /// Unlocked for this visit only; never stored. The app put away locks it
  /// again (review M-2): someone may pick the phone up later.
  bool _unlocked = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_unlocked &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      setState(() => _unlocked = false);
    }
  }

  String? get _userId => ref.read(homeAuthProvider).currentUser?.id;

  String? _country() {
    final userId = _userId;
    if (userId == null) return null;
    final override =
        MeDeviceStore(
          ref.read(sharedPreferencesProvider),
          userId: userId,
        ).countryOverride;
    if (override != null) return override;
    final phone = ref.read(homeAuthProvider).currentUser?.phone;
    if (phone == null || phone.isEmpty) return null;
    return countryOfPhone(phone.startsWith('+') ? phone : '+$phone');
  }

  Future<void> _pickCountry(String? current) async {
    final userId = _userId;
    if (userId == null) return;
    final selected =
        current == null
            ? PhoneCountries.defaultCountry
            : PhoneCountries.all.firstWhere(
              (c) => c.isoCode == current,
              orElse: () => PhoneCountries.defaultCountry,
            );
    await BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      padding: 0,
      widget: PhoneCountryPickerSheet(
        selectedCountry: selected,
        onCountrySelected: (country) async {
          await MeDeviceStore(
            ref.read(sharedPreferencesProvider),
            userId: userId,
          ).setCountryOverride(country.isoCode);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _unlock() async {
    if (await confirmSafetyPin(context)) {
      if (mounted) setState(() => _unlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locked = ref.watch(datingLockProvider);
    // Unknown yet: show nothing rather than a flash of Dating.
    if (!locked.hasValue) return const SizedBox.shrink();
    if (locked.value! && !_unlocked) {
      return SpaceRow(
        title: loc.flow_slotLocked,
        subtitle: loc.flow_slotLockedLine,
        icon: Icons.lock_outline,
        onTap: _unlock,
      );
    }

    final home = widget.home;
    final windowEnds = home.linkDetail.windowEndsAt;
    // The whole window, even with no end date (review M-1, §3.13).
    if (home.link == LinkState.endedWindow) {
      return _SlotCard(
        title:
            windowEnds == null
                ? loc.flow_slotGentleWaitNoDate
                : loc.flow_slotGentleWait(
                  MyDateFormat.toDate(windowEnds.toLocal()),
                ),
        lines: [loc.flow_slotGentleWaitWhy],
        actions: [
          FlowTextLink(
            label: loc.flow_slotHealing,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => openHealing(context, ref),
          ),
        ],
      );
    }

    final open = ref.watch(datingOpenCountriesProvider);
    final enabled = home.dating?.enabled ?? false;
    final notReady = FlowTextLink(
      label: loc.flow_slotNotReady,
      alignment: AlignmentDirectional.centerStart,
      onPressed: () async {
        final outcome = await switchPath(
          context,
          ref,
          to: AppPath.justMe,
          oneTap: true,
          home: widget.home,
        );
        // B4 review M-2: an open shared space is paused or ended first.
        if (outcome == PathChoiceOutcome.relationshipOpen && context.mounted) {
          await showSharedSpaceSheetAfterRefusal(context, widget.home);
        }
      },
    );
    if (!enabled || open.isEmpty) {
      return _SlotCard(
        title: loc.flow_slotClosedTitle,
        lines: [loc.flow_slotClosedBody],
        actions: [notReady],
      );
    }

    String name(String iso) => countryNameFor(
      iso,
      special: {'GB': loc.flow_countryUk, 'US': loc.flow_countryUs},
    );
    final openNames = formatCountryList(
      open,
      nameOf: name,
      pair: loc.flow_listTwo,
    );
    final country = _country();
    if (country == null) {
      return _SlotCard(
        title: loc.flow_slotDatingTitle,
        lines: [loc.flow_slotNotOpenBody(openNames)],
        actions: [
          FlowTextLink(
            label: loc.flow_slotChooseCountry,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _pickCountry(null),
          ),
          notReady,
        ],
      );
    }
    if (!open.contains(country)) {
      return _SlotCard(
        title: loc.flow_slotNotOpenTitle(name(country)),
        lines: [loc.flow_slotNotOpenBody(openNames)],
        actions: [
          FlowTextLink(
            label: loc.flow_slotChangeCountry(name(country)),
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _pickCountry(country),
          ),
          notReady,
        ],
      );
    }
    return _SlotCard(
      title: loc.flow_slotDatingTitle,
      lines: [loc.flow_slotDatingBody],
      actions: [
        FlowPrimaryButton(
          label: loc.flow_slotSetUp,
          onPressed: () => context.push(RouteNames.datingMode),
        ),
        notReady,
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.title,
    required this.lines,
    required this.actions,
  });

  final String title;
  final List<String> lines;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final line in lines) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  line,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.sm),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
