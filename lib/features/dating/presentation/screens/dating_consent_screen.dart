import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingConsentScreen extends ConsumerStatefulWidget {
  const DatingConsentScreen({super.key});

  @override
  ConsumerState<DatingConsentScreen> createState() =>
      _DatingConsentScreenState();
}

class _DatingConsentScreenState extends ConsumerState<DatingConsentScreen> {
  static const _termsVersion = '1.2.0';

  bool _termsAccepted = false;
  bool _dataConsent = false;
  bool _adultsOnlyConfirmed = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dating Mode'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before you start',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Dating Mode uses a small set of your own self-reported Attune signals to offer curated introductions. It cannot predict chemistry, safety, or relationship success.',
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.xl.h),
            _buildConsentCard(
              context,
              value: _termsAccepted,
              onChanged: (value) {
                setState(() => _termsAccepted = value ?? false);
              },
              title: 'I accept the Dating Mode terms and privacy notice.',
              subtitle:
                  'Enrollment and profile activation are separate steps, and you can pause or exit at any time.',
            ),
            Gap(Spacing.md.h),
            _buildConsentCard(
              context,
              value: _dataConsent,
              onChanged: (value) {
                setState(() => _dataConsent = value ?? false);
              },
              title: 'Use my eligible historical summaries to add context.',
              subtitle:
                  'This never includes a former partner\'s profile, messages, or private insights. You can withdraw this later.',
              optionalLabel: 'Optional',
            ),
            Gap(Spacing.md.h),
            _buildConsentCard(
              context,
              value: _adultsOnlyConfirmed,
              onChanged: (value) {
                setState(() => _adultsOnlyConfirmed = value ?? false);
              },
              title: 'I confirm that I am 18 or older.',
              subtitle:
                  'Dating Mode is adults only. This confirmation does not replace the trusted age verification required before profile activation.',
              highlightColor: colorScheme.error,
            ),
            const Spacer(),
            AppButton(
              label: 'Continue',
              onPressed:
                  _termsAccepted && _adultsOnlyConfirmed && !_isLoading
                      ? _handleContinue
                      : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentCard(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
    String? optionalLabel,
    Color? highlightColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color: (highlightColor ?? colorScheme.outline).withValues(
            alpha: 0.12,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: highlightColor ?? colorScheme.primary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (optionalLabel != null)
                  Text(
                    optionalLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                Text(title, style: textTheme.bodyMedium),
                Gap(Spacing.xs.h),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleContinue() async {
    setState(() => _isLoading = true);

    try {
      await ref.read(
        recordDatingConsentProvider((
          termsVersion: _termsVersion,
          dataConsent: _dataConsent,
          adultsOnlyConfirmed: _adultsOnlyConfirmed,
        )).future,
      );

      await ref.read(
        optInToDatingProvider((termsVersion: _termsVersion)).future,
      );

      if (mounted) {
        context.pushReplacementNamed('datingProfile');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dating enrollment is unavailable right now.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
