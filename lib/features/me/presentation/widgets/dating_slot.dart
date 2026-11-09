import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart'
    show HomeSnapshot;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Dating slot at the top of Me, Dating path only (Spec 1 §3.9). Since
/// Spec 2 W3a its body is Spec 2's DatingSection (get_dating_home()). The
/// slot keeps the Dating lock's row: one row until the Safety PIN is
/// entered, for this foreground session only; the unlock is Spec 2's
/// datingUnlockedProvider, shared with every /dating route (R-8).
class DatingSlot extends ConsumerWidget {
  const DatingSlot({super.key, required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    // Spec 2 W3 final fix (I-1, I-1b): the unlock ended with the lock on
    // (or unreadable): every Dating sheet goes, wherever it is in the
    // stack. Spec 1's own sheets on Me stay, with what was typed in them.
    ref.listen<bool>(datingUnlockedProvider, (was, now) {
      if (was == true &&
          !now &&
          (ref.read(datingLockProvider).valueOrNull ?? true)) {
        closeDatingSheets();
      }
    });
    final locked = ref.watch(datingLockProvider);
    // Unknown yet: show nothing rather than a flash of Dating. Spec 2 W3
    // final fix (M-14): unreadable is locked (fail closed), never nothing,
    // so the PIN still leads to Dating settings and Leave.
    if (!locked.hasValue && !locked.hasError) return const SizedBox.shrink();
    if ((locked.hasError || locked.value!) &&
        !ref.watch(datingUnlockedProvider)) {
      return Semantics(
        container: true,
        label: loc.dating_sectionLockedLabel,
        child: SpaceRow(
          title: loc.flow_slotLocked,
          subtitle: loc.flow_slotLockedLine,
          icon: Icons.lock_outline,
          onTap: () async {
            if (await confirmSafetyPin(context)) {
              ref.read(datingUnlockedProvider.notifier).unlock();
            }
          },
        ),
      );
    }
    return const DatingSection();
  }
}
