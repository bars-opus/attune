import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _emailError;
  bool _isEmailValid = false;

  final _emailFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _validateEmail(widget.initialEmail);
    }
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (!mounted) return null;

    final result = ValidationUtils.validateEmail(
      value,
      options: const EmailValidationOptions(
        checkDisposableDomains: true,
        allowPlusAlias: true,
      ),
    );

    final error = result.toErrorString();

    if (mounted) {
      setState(() {
        _emailError = error;
        _isEmailValid = error == null;
      });
    }

    return error;
  }

  Future<void> _handleSendResetEmail() async {
    final loc = AppLocalizations.of(context)!;

    if (_emailController.text.isEmpty) {
      context.showErrorSnackbar(loc.commonEnterEmailAndRetry);
      return;
    }
    if (!_formKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      final authOps = ref.read(authOperationsProvider);
      await authOps.resetPassword(_emailController.text.trim());

      if (mounted) {
        context.go(
          RouteNames.passwordResetSentScreen,
          extra: _emailController.text.trim(),
        );
      }
    } on AuthException catch (e) {
      if (mounted) context.showErrorSnackbar(e.message);
    } catch (_) {
      if (mounted)
        context.showErrorSnackbar(loc.commonSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFieldFeedback(String field, String? error) {
    if (!mounted) return;

    final loc = AppLocalizations.of(context);

    if (error != null) {
      final message = '$field: $error';
      context.showErrorSnackbar(message);
    } else {
      final message = loc?.commonFieldIsValid(field) ?? '$field is valid';
      context.showSuccessSnackbar(backgroundColor: Colors.green, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: AppIconButton(icon: Icons.close, onPressed: () => context.pop()),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md),
          children: [
            const Gap(Spacing.md),
            IconAvatar(
              icon: Icons.lock_reset_outlined,
              iconColor: colorScheme.primary,
              size: 100,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
              avatarRadiusSize: 100,

              circularRadius: 100.r,
            ),

            const Gap(Spacing.md),
            Text(
              loc.authForgotPasswordTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(12.h),
            Text(
              loc.authForgotPasswordSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(Spacing.md),

            AppTextFormField(
              controller: _emailController,
              label: loc.loginEmailLabel,
              hintText: loc.loginEmailHint,
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              focusNode: _emailFocusNode,
              onFieldSubmitted: (_) {
                _emailFocusNode.unfocus();
                _handleSendResetEmail();
              },
              validator: _validateEmail,
              onChanged: (value) => _validateEmail(value),
              // errorText: _emailError,
              suffixIcon:
                  _emailController.text.isNotEmpty
                      ? GestureDetector(
                        onTap:
                            () =>
                                _showFieldFeedback(loc.emailTitle, _emailError),
                        child: Icon(
                          _isEmailValid ? Icons.check_circle : Icons.error,
                          color: _isEmailValid ? Colors.green : Colors.red,
                        ),
                      )
                      : null,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
            ),
            const Gap(Spacing.xxl),
            AppButton(
              label: loc.authSendResetLink,
              onPressed: _isLoading ? null : _handleSendResetEmail,
              isLoading: _isLoading,
              elevation: 1,
              size: ButtonSize.small,
              width: double.infinity,
              padding: Spacing.horizontalMd,
              height: 40.h,
            ),

            Gap(16.h),
            TextButton(
              onPressed: _isLoading ? null : () => context.go(RouteNames.login),
              child: Text(
                loc.authBackToSignIn,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14.sp,
                ),
              ),
            ),
            const Gap(Spacing.md),
          ],
        ),
      ),
    );
  }
}
