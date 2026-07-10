import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordlessAuthStep extends StatefulWidget {
  const PasswordlessAuthStep({
    super.key,
    required this.onVerified,
    PasswordlessAuthService? authService,
  }) : _authService = authService;

  final VoidCallback onVerified;
  final PasswordlessAuthService? _authService;

  @override
  State<PasswordlessAuthStep> createState() => _PasswordlessAuthStepState();
}

class _PasswordlessAuthStepState extends State<PasswordlessAuthStep> {
  late final PasswordlessAuthService _authService =
      widget._authService ?? PasswordlessAuthService();

  final _contactController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isSending = false;
  bool _isVerifying = false;
  bool _otpSent = false;
  String? _statusMessage;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (_authService.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onVerified());
    }
    _authSubscription = _authService.authStateChanges.listen((state) {
      if (state.session?.user != null && mounted) {
        widget.onVerified();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _contactController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      key: const ValueKey('passwordless-auth-step'),
      padding: EdgeInsets.all(Spacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify one contact method',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Gap(Spacing.smMd.h),
          Text(
            'Attune uses phone verification at launch to keep account identity tied to a verified number.',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          Gap(Spacing.lg.h),
          AppTextFormField(
            controller: _contactController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            label: 'Phone number',
            hintText: '+1 610 342 7892',
            textInputAction: TextInputAction.next,
            enabled: !_isBusy,
          ),
          if (_otpSent) ...[
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              label: 'Verification code',
              hintText: '123456',
              enabled: !_isVerifying,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _verifyPhoneOtp(),
            ),
          ],
          if (_statusMessage != null) ...[
            Gap(Spacing.smMd.h),
            SemanticContainerWidget(
              content: _statusMessage!,
              icon: Icons.info_outline,
              title: 'Verification',
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              borderColor: colorScheme.primary,
              iconColor: colorScheme.primary,
              textTheme: textTheme,
            ),
          ],
          const Spacer(),
          if (!_authService.isConfigured)
            Padding(
              padding: EdgeInsets.only(bottom: Spacing.smMd.h),
              child: SemanticContainerWidget(
                content:
                    'Supabase is not configured in this local run. Add the new Attune Supabase values to enable verification.',
                icon: Icons.info_outline,
                title: 'Configuration needed',
                backgroundColor: colorScheme.error.withValues(alpha: 0.1),
                borderColor: colorScheme.error,
                iconColor: colorScheme.error,
                textTheme: textTheme,
              ),
            ),
          AppButton(
            label: _primaryActionLabel,
            onPressed:
                _isPrimaryActionEnabled
                    ? (_otpSent ? _verifyPhoneOtp : _requestPhoneOtp)
                    : null,
            isLoading: _isBusy,
            size: ButtonSize.small,
            height: 40.h,
          ),
        ],
      ),
    );
  }

  bool get _isBusy => _isSending || _isVerifying;

  bool get _isPrimaryActionEnabled {
    if (!_authService.isConfigured || _isBusy) return false;
    if (_contactController.text.trim().isEmpty) return true;
    return true;
  }

  String get _primaryActionLabel {
    if (_isSending) return 'Sending...';
    if (_isVerifying) return 'Verifying...';
    if (_otpSent) return 'Verify code';
    return 'Send verification code';
  }

  Future<void> _requestPhoneOtp() async {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) {
      _showMessage('Enter your phone number to continue.');
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    try {
      await _authService.requestPhoneOtp(contact);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _statusMessage = 'We sent a verification code to your phone.';
      });
    } catch (error) {
      _showMessage(_authService.userSafeMessage(error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final phone = _contactController.text.trim();
    final token = _otpController.text.trim();

    if (phone.isEmpty || token.isEmpty) {
      _showMessage('Enter the code we sent to your phone.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });

    try {
      final result = await _authService.verifyPhoneOtp(
        phoneNumber: phone,
        token: token,
      );
      if (!mounted) return;
      if (result.isVerified) {
        widget.onVerified();
      } else {
        _showMessage('Verification did not complete. Try the code again.');
      }
    } catch (error) {
      _showMessage(_authService.userSafeMessage(error));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
  }
}
