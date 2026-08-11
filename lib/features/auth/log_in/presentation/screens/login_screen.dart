import 'dart:async';

import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/state/phone_auth_providers.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/login_code_step.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/login_phone_step.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _otpResendCooldown = Duration(seconds: 60);

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();

  late final PasswordlessAuthService _authService = PasswordlessAuthService();
  late final EulaAcceptanceService _eulaService = EulaAcceptanceService();

  TabController? _tabController;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _otpResendTimer;
  int _currentTabIndex = 0;
  int _resendSecondsRemaining = 0;
  bool _isSending = false;
  bool _isVerifying = false;
  bool _otpSent = false;
  bool _hasLeftForOnboarding = false;
  OtpChannel _otpChannel = OtpChannel.sms;

  @override
  void initState() {
    super.initState();
    if (_authService.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToOnboarding());
    } else {
      // Post-frame: LoginScreen is presented both as a route and inside a
      // modal bottom sheet (see _goToOnboarding's note below), so the field
      // needs to actually be laid out before it can take focus. Skipped
      // entirely when already signed in — the screen navigates away above
      // before anyone would see the keyboard anyway.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _phoneFocusNode.requestFocus();
      });
    }
    _authSubscription = _authService.authStateChanges.listen((state) {
      if (state.session?.user != null && mounted) {
        _goToOnboarding();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _otpResendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    final isBusy = _isSending || _isVerifying;
    final selectedCountry = ref.watch(selectedPhoneCountryProvider);

    // A Scaffold (not just Material) so ScaffoldMessenger.showSnackBar has
    // a descendant to attach to. Harmless as a modal-sheet child (a nested
    // Scaffold works fine there), but required now that this screen is
    // also reached as the bare /login route (see OnboardingGate) with no
    // ancestor Scaffold of its own to fall back on — every showSuccess/
    // ErrorSnackbar call below crashed with "no descendant Scaffolds"
    // until this existed on that path.
    return Scaffold(
      backgroundColor: colorScheme.neutral,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TabsWithContent(
              showCloseIcon: true,
              onClosePressed: () => _handleClose(context),
              appBartext: loc.commonContinue,
              appBarOnPressed: isBusy ? null : _handlePrimaryAction,
              onControllerCreated: (controller) => _tabController = controller,
              useNestedScrollMode: true,
              enableSwipe: false,
              scrollable: false,
              onTabChangeRequest: (fromIndex, toIndex) {
                if (toIndex == 1 && !_otpSent) {
                  _requestPhoneOtp();
                  return false;
                }
                return true;
              },
              onTabChanged: (index) {
                if (!mounted) return;
                setState(() => _currentTabIndex = index);
                // Fires on every arrival at the Code tab, not just the one
                // right after requesting a code (see _requestPhoneOtp's own
                // post-frame requestFocus below) — this also covers a manual
                // swipe/tap back to an already-_otpSent Code tab, which
                // onTabChangeRequest lets through with no focus call of its
                // own. Post-frame for the same reason as everywhere else here:
                // the tab's fields aren't laid out yet the instant this fires.
                if (index == 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _otpFocusNode.requestFocus();
                  });
                }
              },
              tabs: [
                AppTabItem(
                  label: 'Phone',
                  // icon:
                  //     _currentTabIndex == 0
                  //         ? Icons.phone_iphone
                  //         : Icons.phone_iphone_outlined,
                  content: LoginPhoneStep(
                    controller: _phoneController,
                    focusNode: _phoneFocusNode,
                    country: selectedCountry,
                    enabled: !isBusy,
                    authConfigured: _authService.isConfigured,
                    otpChannel: _otpChannel,
                    onCountryChanged:
                        (country) =>
                            ref
                                .read(selectedPhoneCountryProvider.notifier)
                                .state = country,
                    onOtpChannelChanged: (channel) {
                      setState(() => _otpChannel = channel);
                    },
                    onSubmitted: (_) => _requestPhoneOtp(),
                  ),
                ),
                AppTabItem(
                  label: 'Code',
                  // icon: _currentTabIndex == 1 ? Icons.sms : Icons.sms_outlined,
                  content: LoginCodeStep(
                    controller: _otpController,
                    focusNode: _otpFocusNode,
                    enabled: !isBusy && _otpSent,
                    phoneNumber: _normalizedPhoneNumber(selectedCountry),
                    resendSecondsRemaining: _resendSecondsRemaining,
                    onSubmitted: (_) => _verifyPhoneOtp(),
                    onResend:
                        isBusy || _resendSecondsRemaining > 0
                            ? null
                            : _requestPhoneOtp,
                  ),
                ),
              ],
              initialIndex: 0,
              showContent: true,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePrimaryAction() {
    return _otpSent && _currentTabIndex == 1
        ? _verifyPhoneOtp()
        : _requestPhoneOtp();
  }

  Future<void> _requestPhoneOtp() async {
    if (!_authService.isConfigured) {
      // Release builds must not name the backend (spec §Failure Modes: no
      // project refs / internal config in UI errors). In debug this is a local
      // setup mistake, so keep the actionable hint for developers only.
      context.showErrorSnackbar(
        kDebugMode
            ? 'Backend not configured for this run. Pass --dart-define-from-file=.env.json'
            : 'Phone sign-in is unavailable right now. Please try again later.',
      );
      return;
    }

    final country = ref.read(selectedPhoneCountryProvider);
    final validation = _validatePhoneNumber(country);
    if (!validation.isValid) {
      context.showErrorSnackbar(
        validation.errorMessage ?? 'Enter a valid phone number.',
      );
      _phoneFocusNode.requestFocus();
      return;
    }

    final phone = _normalizedPhoneNumber(country);
    setState(() => _isSending = true);

    try {
      await _authService.requestPhoneOtp(phone, channel: _otpChannel);
      if (!mounted) return;
      setState(() => _otpSent = true);
      _startOtpResendCountdown();
      // animateTo triggers TabsWithContent's onTabChanged once the switch
      // lands on index 1, which is what requests focus on the Code tab's
      // fields — see that callback for why it's post-frame and why it's the
      // one place this is handled rather than duplicated here too.
      _tabController?.animateTo(1);
      context.showSuccessSnackbar('Verification code sent to $phone.');
    } catch (error) {
      if (mounted) {
        context.showErrorSnackbar(_authService.userSafeMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final country = ref.read(selectedPhoneCountryProvider);
    final phone = _normalizedPhoneNumber(country);
    final token = _otpController.text.trim();

    final validation = _validatePhoneNumber(country);
    if (!validation.isValid) {
      context.showErrorSnackbar(
        validation.errorMessage ?? 'Check your phone number and try again.',
      );
      _tabController?.animateTo(0);
      return;
    }

    if (token.length < 4) {
      context.showErrorSnackbar(
        'Enter the verification code we sent to your phone.',
      );
      _otpFocusNode.requestFocus();
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final result = await _authService.verifyPhoneOtp(
        phoneNumber: phone,
        token: token,
      );
      if (!mounted) return;
      if (result.isVerified) {
        context.showSuccessSnackbar('Phone number verified.');
        _goToOnboarding();
      } else {
        context.showErrorSnackbar('Verification did not complete. Try again.');
      }
    } catch (error) {
      if (mounted) {
        context.showErrorSnackbar(_authService.userSafeMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String _normalizedPhoneNumber(PhoneCountry country) {
    return ValidationUtils.normalizePhoneNumber(
      dialCode: country.dialCode,
      nationalNumber: _phoneController.text,
      isoCode: country.isoCode,
    );
  }

  ValidationResult _validatePhoneNumber(PhoneCountry country) {
    return ValidationUtils.validatePhoneNumberForCountry(
      _phoneController.text,
      isoCode: country.isoCode,
      dialCode: country.dialCode,
      countryName: country.name,
    );
  }

  void _startOtpResendCountdown() {
    _otpResendTimer?.cancel();
    setState(() {
      _resendSecondsRemaining = _otpResendCooldown.inSeconds;
    });

    _otpResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
        return;
      }

      setState(() => _resendSecondsRemaining--);
    });
  }

  Future<void> _goToOnboarding() async {
    if (!mounted || _hasLeftForOnboarding) return;

    // Three separate paths can reach here for a single sign-in: the
    // already-authenticated check in initState, the authStateChanges listener,
    // and the _verifyPhoneOtp success handler (the listener and the handler
    // both fire on one successful OTP). Navigating more than once would pop the
    // sheet AND then a real page below it, so this is latched: first caller
    // wins, the rest are no-ops.
    //
    // The latch MUST stay set across the EULA await below. It previously
    // reset to false on the not-accepted path, which turned a slow consent
    // sheet into a re-entrancy hole: verifyOTP fires authStateChange(signedIn)
    // while the sheet is still open, the listener above calls this again, and
    // each pass re-triggered navigation — the observed storm of repeated
    // "going to /onboarding" redirects that tore the sheet's own context down
    // and made EulaGate return false (a synthetic "decline" nobody performed),
    // which then signed the freshly-verified user straight back out.
    _hasLeftForOnboarding = true;

    // Consent is gated here rather than before the phone step because whether
    // this is a first-time user is only knowable once they're authenticated.
    // Returning users who already accepted the current version pass straight
    // through; a declining user is returned to the unauthenticated state
    // rather than being let in without agreeing.
    if (!await _ensureEulaAccepted()) {
      // Only re-arm when this widget is still alive to retry. If it isn't,
      // the "decline" was a teardown artifact, not a real answer, and
      // re-arming would let a stale listener event restart the whole flow.
      if (mounted) _hasLeftForOnboarding = false;
      return;
    }
    if (!mounted) return;

    // LoginScreen is presented BOTH as a route (/login) and inside a modal
    // bottom sheet (from LoginProfile). `context.go` swaps the page stack
    // underneath the modal without dismissing it, which would leave the user
    // stranded behind the login sheet after a successful verification.
    // showModalBottomSheet pushes a PopupRoute, so that — and only that — is
    // what we dismiss here; when LoginScreen is the /login page the enclosing
    // route is a GoRouter page, not a PopupRoute, and we route directly.
    final route = ModalRoute.of(context);
    if (route is PopupRoute) {
      Navigator.of(context).pop();
    }

    // Any pending couples-invite code (stashed by main.dart's deep-link
    // handler, or already sitting there from a prior session) is accepted
    // by OnboardingGate itself once it sees an authenticated visitor with a
    // pending code — see its _acceptPendingInvite. Nothing else to do here.
    context.go(RouteNames.onboarding);
  }

  /// Same PopupRoute distinction _goToOnboarding uses: as a modal sheet, a
  /// plain pop correctly reveals whatever real screen was already showing
  /// underneath. As the /login page (reached e.g. via OnboardingGate
  /// routing an unauthenticated invitee here — see its own doc), that page
  /// IS the base of the stack; GoRouter's earlier context.go(login) replaced
  /// whatever was there, so a plain pop has nothing left to reveal and left
  /// the invitee on an empty screen. Route home instead in that case.
  void _handleClose(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is PopupRoute) {
      Navigator.of(context).pop();
    } else {
      context.go(RouteNames.home);
    }
  }

  /// Returns true when the user may proceed. On an explicit DECLINE the
  /// session is ended — it is already valid at this point, so leaving it
  /// would let the next launch skip the consent gate via the initState
  /// already-signed-in check.
  ///
  /// An [EulaOutcome.unavailable] result deliberately does NOT sign out: the
  /// prompt never got a real answer (torn-down context, or a failed
  /// acceptance write), and ending a freshly-verified session over that is
  /// what previously dumped users back to a signed-out home screen straight
  /// after a successful OTP. The session survives; the consent gate simply
  /// runs again on the next attempt, which is the safe direction to fail.
  Future<bool> _ensureEulaAccepted() async {
    final outcome = await EulaGate.ensureAccepted(
      context,
      service: _eulaService,
    );
    if (outcome == EulaOutcome.declined) {
      await _authService.signOut();
    }
    return outcome.mayProceed;
  }
}
