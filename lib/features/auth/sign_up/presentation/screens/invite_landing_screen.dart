import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// RI-1 and RI-2 (`/invite`, pre-auth; Spec 1 §3.8). With a code from a
/// link (the anonymous slot, §5.5) it says only that someone invited you:
/// no inviter name before sign-in proves the phone (10 F-10). Without one,
/// it asks for the code first. Joining (RI-3) comes after sign-in, in W4b;
/// until then the signed-in gate accepts the stored code as today.
class InviteLandingScreen extends ConsumerStatefulWidget {
  const InviteLandingScreen({super.key});

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  final _code = TextEditingController();
  late bool _hasCode;
  bool _invalid = false;

  /// One per failed submit, so the same message is read out again.
  int _errorCount = 0;

  OnboardingStore get _anonymousStore => OnboardingStore(
    ref.read(sharedPreferencesProvider),
    scope: OnboardingStore.anonymousScope,
  );

  @override
  void initState() {
    super.initState();
    _hasCode = _anonymousStore.pendingInviteCode != null;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      setState(() {
        _invalid = true;
        _errorCount++;
      });
      return;
    }
    await OnboardingStore.storeInviteFromLink(
      ref.read(sharedPreferencesProvider),
      code,
    );
    if (mounted) {
      setState(() {
        _invalid = false;
        _hasCode = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    void back() => context.go(RouteNames.welcome);

    if (!_hasCode) {
      return FlowFrame(
        title: loc.flow_inviteCodeTitle,
        onBack: back,
        body: FlowTextField(
          controller: _code,
          label: loc.flow_inviteCodeLabel,
          errorText: _invalid ? loc.flow_inviteCodeError : null,
          errorCount: _errorCount,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(12)],
          autofocus: true,
          onSubmitted: (_) => _submitCode(),
        ),
        actions: [
          FlowPrimaryButton(label: loc.flow_continue, onPressed: _submitCode),
        ],
      );
    }

    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_inviteTitle,
      onBack: back,
      body: Text(
        loc.flow_inviteBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_inviteCreate,
          onPressed: () => context.go(WelcomeScreen.signUpLocation('invite')),
        ),
        FlowSecondaryButton(
          label: loc.flow_welcomeHaveAccount,
          onPressed:
              () => context.go(WelcomeScreen.signUpLocation('returning')),
        ),
      ],
    );
  }
}
