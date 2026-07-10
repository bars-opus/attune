import 'dart:async';
import 'package:attune/features/auth/utility/auth_exports.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;

  const VerifyEmailScreen({super.key, required this.email});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _resendCooldown = 60;
  int _secondsRemaining = 0;
  Timer? _cooldownTimer;
  bool _isResending = false;
  ProviderSubscription<AsyncValue<Object?>>? _authSub;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    // Auto-navigate when the user's session is created (email confirmed on
    // any device — the Supabase auth stream fires when getSessionFromUrl runs
    // in main.dart, or on the next token refresh if confirmed elsewhere).
    _authSub = ref.listenManual<AsyncValue<Object?>>(authStateProvider, (_, next) {
      if (next.valueOrNull != null && mounted) {
        context.go(RouteNames.createUsername);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.close();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _secondsRemaining = _resendCooldown);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendEmail() async {
    if (_secondsRemaining > 0 || _isResending) return;

    final loc = AppLocalizations.of(context)!;

    setState(() => _isResending = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.resendConfirmationEmail(widget.email);
      if (mounted) {
        context.showSuccessSnackbar(loc.authConfirmationResent);
        _startCooldown();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackbar(loc.authResendFailed);
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Gap(40.h),
              // Icon
              Container(
                width: 96.w,
                height: 96.w,
                decoration: BoxDecoration(
                  color: theme.appColors.appColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 48.sp,
                  color: theme.appColors.appColor,
                ),
              ),
              Gap(32.h),
              // Title
              Text(
                loc.authVerifyEmailTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              Gap(12.h),
              // Subtitle
              Text(
                loc.authVerifyEmailSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              Gap(4.h),
              Text(
                widget.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              Gap(8.h),
              Text(
                loc.authVerifyEmailNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // Resend button
              _ResendButton(
                secondsRemaining: _secondsRemaining,
                isResending: _isResending,
                onResend: _resendEmail,
              ),
              Gap(16.h),
              // Back to login
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(
                  loc.authBackToSignIn,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 14.sp,
                  ),
                ),
              ),
              Gap(32.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResendButton extends StatelessWidget {
  final int secondsRemaining;
  final bool isResending;
  final VoidCallback onResend;

  const _ResendButton({
    required this.secondsRemaining,
    required this.isResending,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final canResend = secondsRemaining == 0 && !isResending;
    final theme = Theme.of(context);
    final primary = theme.appColors.appColor;

    return SizedBox(
      width: double.infinity,
      height: 52.h,
      child: ElevatedButton(
        onPressed: canResend ? onResend : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          disabledBackgroundColor: primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child:
            isResending
                ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Text(
                  secondsRemaining > 0
                      ? loc.authResendEmailCooldown(secondsRemaining)
                      : loc.authResendEmailButton,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
      ),
    );
  }
}
