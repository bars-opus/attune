import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() =>
      _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  String? _passwordError;
  String? _confirmPasswordError;
  bool _isPasswordValid = false;
  bool _isConfirmPasswordValid = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdatePassword() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    final loc = AppLocalizations.of(context)!;
    final newPassword = _passwordController.text;
    setState(() => _isLoading = true);

    try {
      await ref.read(authOperationsProvider).updatePassword(newPassword);
      _passwordController.clear();
      _confirmPasswordController.clear();

      final notifier = ref.read(routingNotifierProvider);
      // Clear recovery mode first so the router won't redirect back here
      // when signOut triggers an auth state change.
      notifier.setRecoveryMode(false);
      await ref.read(authOperationsProvider).signOut();
      // Bypass the 100ms debounce so the router sees null user immediately
      // and redirects to /login rather than /home.
      notifier.clearUser();
    } on AuthException catch (e) {
      if (mounted) context.showErrorSnackbar(e.message);
      return;
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar(loc.commonSomethingWentWrong);
      }
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    context.showSuccessSnackbar(loc.authUpdatePasswordSuccess);
    context.go(RouteNames.login);
  }

  String? _validatePassword(String? value) {
    if (!mounted) return null;
    final result = ValidationUtils.validatePassword(
      value,
      requirements: PasswordRequirements.medium,
    );
    final error = result.toErrorString();
    if (mounted) {
      setState(() {
        _passwordError = error;
        _isPasswordValid = error == null;
      });
    }
    return error;
  }

  String? _validateConfirmPassword(String? value) {
    if (!mounted) return null;
    final loc = AppLocalizations.of(context)!;

    String? error;
    if (value == null || value.isEmpty) {
      error = loc.commonPasswordConfirmRequired;
    } else if (value != _passwordController.text) {
      error = loc.commonPasswordsDoNotMatch;
    }
    if (mounted) {
      setState(() {
        _confirmPasswordError = error;
        _isConfirmPasswordValid = error == null;
      });
    }
    return error;
  }

  void _showFieldFeedback(String field, String? error) {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;

    if (error != null) {
      context.showErrorSnackbar('$field: $error');
    } else {
      final message = loc.commonFieldIsValid(field);
      context.showSuccessSnackbar(backgroundColor: Colors.green, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: AppIconButton(
          icon: Icons.close,
          onPressed: () => context.go(RouteNames.home),
        ),
      ),
      body: Form(
        
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md),
          children: [
          const Gap(Spacing.sm),
          Text(
            loc.authUpdatePasswordTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(Spacing.md),
          IconAvatar(
            icon: Icons.lock_outline,
            iconColor: colorScheme.primary,
            size: 100,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            avatarRadiusSize: 100,
            circularRadius: 100.r,
          ),
          const Gap(Spacing.md),
          AppTextFormField(
            controller: _passwordController,
            label: loc.passwordTitle,
            hintText: loc.loginPasswordHint,
            prefixIcon: Icons.lock_outline,
            obscureText: _obscurePassword,
            enabled: !_isLoading,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_passwordController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () =>
                        _showFieldFeedback(loc.passwordTitle, _passwordError),
                    child: Icon(
                      _isPasswordValid ? Icons.check_circle : Icons.error,
                      color: _isPasswordValid ? Colors.green : Colors.red,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colorScheme.primary,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                ),
              ],
            ),
            validator: _validatePassword,
            onChanged: (value) {
              _validatePassword(value);
              _validateConfirmPassword(_confirmPasswordController.text);
            },
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
          ),
          AppTextFormField(
            controller: _confirmPasswordController,
            label: loc.commonConfirmPasswordLabel,
            hintText: loc.commonConfirmPasswordHint,
            prefixIcon: Icons.lock_outline,
            obscureText: _obscurePassword,
            enabled: !_isLoading,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_confirmPasswordController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showFieldFeedback(
                        loc.commonConfirmPasswordLabel, _confirmPasswordError),
                    child: Icon(
                      _isConfirmPasswordValid
                          ? Icons.check_circle
                          : Icons.error,
                      color:
                          _isConfirmPasswordValid ? Colors.green : Colors.red,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    color: colorScheme.primary,
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                ),
              ],
            ),
            validator: _validateConfirmPassword,
            onChanged: (value) => _validateConfirmPassword(value),
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleUpdatePassword(),
          ),
          const Gap(Spacing.md),
          AppButton(
            label: loc.authUpdatePasswordButton,
            onPressed: _isLoading ? null : _handleUpdatePassword,
            isLoading: _isLoading,
            elevation: 1,
            size: ButtonSize.small,
            width: double.infinity,
            padding: Spacing.horizontalMd,
            height: 40.h,
          ),
          const Gap(Spacing.md),
        ],
      ),
      ),
    );
  }
}
