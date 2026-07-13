import 'dart:async';

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
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
    final loc = AppLocalizations.of(context)!;
    final isBusy = _isSending || _isVerifying;
    final selectedCountry = ref.watch(selectedPhoneCountryProvider);

    return SafeArea(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: TabsWithContent(
          showCloseIcon: true,
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
            if (mounted) setState(() => _currentTabIndex = index);
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
                        ref.read(selectedPhoneCountryProvider.notifier).state =
                            country,
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
      _tabController?.animateTo(1);
      _otpFocusNode.requestFocus();
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

  void _goToOnboarding() {
    if (!mounted || _hasLeftForOnboarding) return;

    // Three separate paths can reach here for a single sign-in: the
    // already-authenticated check in initState, the authStateChanges listener,
    // and the _verifyPhoneOtp success handler (the listener and the handler
    // both fire on one successful OTP). Navigating more than once would pop the
    // sheet AND then a real page below it, so this is latched: first caller
    // wins, the rest are no-ops.
    _hasLeftForOnboarding = true;

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

    context.go(RouteNames.onboarding);
  }
}
