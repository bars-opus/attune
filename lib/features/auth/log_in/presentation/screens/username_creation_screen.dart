import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:attune/core/widgets/text_field_loading_indicator.dart';

class UsernameCreationScreen extends ConsumerStatefulWidget {
  const UsernameCreationScreen({super.key});

  @override
  ConsumerState<UsernameCreationScreen> createState() =>
      _UsernameCreationScreenState();
}

class _UsernameCreationScreenState
    extends ConsumerState<UsernameCreationScreen> {
  final _controller = TextEditingController();
  final _userNameFocusNode = FocusNode();

  // Local UI state
  String? _usernameError;
  bool _isChecking = false;
  bool _isAvailable = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // No need to initialize service here anymore
  }

  @override
  void dispose() {
    _userNameFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability(String value) async {
    final loc = AppLocalizations.of(context)!;

    if (value.length < 3) {
      setState(() {
        _usernameError = loc.authUsernameMinLength(3);
        _isAvailable = false;
        _isChecking = false;
      });
      return;
    }
    if (value.length > 30) {
      setState(() {
        _usernameError = loc.authUsernameMaxLength(30);
        _isAvailable = false;
        _isChecking = false;
      });
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      setState(() {
        _usernameError = loc.authUsernameFormatError;
        _isAvailable = false;
        _isChecking = false;
      });
      return;
    }

    // All local validation passed — mark as checking and clear previous state.
    setState(() {
      _isChecking = true;
      _isAvailable = false;
      _usernameError = null;
    });

    try {
      // Use the pure UsernameService via provider
      final usernameService = ref.read(usernameServiceProvider);
      final isAvailable = await usernameService.isUsernameAvailable(value);

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isAvailable = isAvailable;
          _usernameError = isAvailable ? null : loc.authUsernameTaken;
        });
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackbar(loc.authUsernameCheckError);

        setState(() {
          _isChecking = false;
          _isAvailable = false;
          _usernameError = loc.authUsernameCheckError;
        });
      }
    }
  }

  Future<void> _saveUsername() async {
    final username = _controller.text.trim();
    if (username.isEmpty || !_isAvailable) return;

    final loc = AppLocalizations.of(context)!;

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('No user logged in');

      final repo = ref.read(profileRepositoryProvider);
      // createProfile is now an idempotent UPSERT — safe to call even if
      // _handleNewUser in app.dart already inserted the row on warm sign-in.
      await repo.createProfile(user.id);
      final updatedProfile = await repo.updateUsername(user.id, username);

      // Push the new profile directly into RoutingNotifier so the GoRouter
      // redirect sees hasUsername=true on the same frame and routes to /home
      // instead of bouncing back to /createUsername. Without this, the redirect
      // would re-fire before currentUserProfileProvider refreshes via invalidate.
      ref.read(routingNotifierProvider).updateProfile(updatedProfile);
      ref.invalidate(currentUserProfileProvider);

      if (mounted) {
        context.showSuccessSnackbar(loc.authUsernameSavedSuccess);
        // go() resets the GoRouter stack so the user can't back into createUsername
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        // The repository converts a unique-violation into a friendly Exception
        // message; show that directly. Other errors get a generic message so
        // we never leak DB internals or stack details to the user.
        final friendly = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : loc.authUsernameSaveError;
        context.showErrorSnackbar(friendly);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final loc = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text(
          loc.authUsernameScreenTitle,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Gap(Spacing.lg.h),
            Text(
              loc.authUsernameScreenSubtitle,
              style: textTheme.bodyMedium!.copyWith(
                color: colorScheme.onBackground,
              ),
            ),
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _controller,
              focusNode: _userNameFocusNode,
              label: loc.authUsernameLabel,
              hintText: loc.authUsernameHint,
              keyboardType: TextInputType.text,
              onChanged: _checkAvailability,
              onFieldSubmitted: (_) {
                if (_isAvailable && !_isSubmitting) {
                  _saveUsername();
                }
              },
              errorText: _usernameError,
              suffixIcon:
                  _isChecking
                      ? TextFieldLoadingIndicator()
                      : (_isAvailable
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null),
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.done,
              enabled: !_isSubmitting,
            ),
            const Spacer(),
            AppButton(
              elevation: 0,
              label: loc.commonContinue,
              onPressed:
                  (_isAvailable && !_isSubmitting) ? _saveUsername : null,
              customColor:
                  _isAvailable ? colorScheme.primary : colorScheme.background,
              size: ButtonSize.small,
              width: double.infinity,
              padding: Spacing.horizontalMd,
              height: 40.h,
            ),
          ],
        ),
      ),
    );
  }
}
