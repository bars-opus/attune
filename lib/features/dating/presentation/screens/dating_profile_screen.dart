import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingProfileScreen extends ConsumerStatefulWidget {
  const DatingProfileScreen({super.key});

  @override
  ConsumerState<DatingProfileScreen> createState() =>
      _DatingProfileScreenState();
}

class _DatingProfileScreenState extends ConsumerState<DatingProfileScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  String _selectedCity = '';
  String _selectedIntention = '';
  int _minAge = 25;
  int _maxAge = 40;
  bool _isLoading = false;

  final List<String> _cities = const [
    'Accra',
    'Kumasi',
    'Tema',
    'Takoradi',
    'Cape Coast',
    'Tamale',
  ];

  final List<String> _intentions = const [
    'Long-term relationship',
    'Intentional dating',
    'Still figuring it out',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await ref.read(datingProfileProvider.future);
    if (!mounted || profile == null) {
      return;
    }

    setState(() {
      _displayNameController.text = profile['display_name'] as String? ?? '';
      _bioController.text = profile['bio'] as String? ?? '';
      _selectedCity = profile['city_region_code'] as String? ?? '';
      _selectedIntention = profile['relationship_intention'] as String? ?? '';
      _minAge = (profile['min_age'] as num?)?.toInt() ?? _minAge;
      _maxAge = (profile['max_age'] as num?)?.toInt() ?? _maxAge;
    });
  }

  bool get _isValid =>
      _displayNameController.text.trim().isNotEmpty &&
      _selectedCity.isNotEmpty &&
      _selectedIntention.isNotEmpty &&
      _minAge <= _maxAge;

  Future<void> _saveAndActivate() async {
    if (!_isValid || _isLoading) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final savedProfile = await ref.read(
        saveDatingProfileProvider((
          displayName: _displayNameController.text.trim(),
          cityRegionCode: _selectedCity,
          relationshipIntention: _selectedIntention,
          minAge: _minAge,
          maxAge: _maxAge,
          bio:
              _bioController.text.trim().isEmpty
                  ? null
                  : _bioController.text.trim(),
        )).future,
      );

      if (savedProfile['moderation_state'] == 'pending') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile saved for review.')),
          );
          Navigator.pop(context);
        }
        return;
      }

      await ref.read(activateDatingProfileProvider.future);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DatingDashboardScreen()),
          (route) => route.isFirst,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile saved, but activation requirements are not complete.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your dating profile'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A calm, honest introduction',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Attune keeps photos secondary and shows an Alignment preview with modest explanations. Your exact date of birth stays out of this profile.',
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.xl.h),
            Text(
              'Display name',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _displayNameController,
              label: 'Display name',
              hintText: 'First name or chosen display name',
              maxLength: 50,
            ),
            Gap(Spacing.lg.h),
            Text(
              'City or region',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            _buildDropdown(
              context,
              value: _selectedCity.isEmpty ? null : _selectedCity,
              hint: 'Select your city or region',
              items: _cities,
              onChanged: (value) => setState(() => _selectedCity = value ?? ''),
            ),
            Gap(Spacing.lg.h),
            Text(
              'Relationship intention',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            _buildDropdown(
              context,
              value: _selectedIntention.isEmpty ? null : _selectedIntention,
              hint: 'Select your intention',
              items: _intentions,
              onChanged: (value) {
                setState(() => _selectedIntention = value ?? '');
              },
            ),
            Gap(Spacing.lg.h),
            Text(
              'Preferred age range',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.xs.h),
            Text(
              'This is a matching filter, not your displayed age.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.sm.h),
            Row(
              children: [
                Expanded(
                  child: _buildAgePicker(
                    context,
                    label: 'Min',
                    value: _minAge,
                    onChanged: (value) => setState(() => _minAge = value ?? 18),
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: _buildAgePicker(
                    context,
                    label: 'Max',
                    value: _maxAge,
                    onChanged: (value) => setState(() => _maxAge = value ?? 40),
                  ),
                ),
              ],
            ),
            Gap(Spacing.lg.h),
            Text(
              'Bio (optional)',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _bioController,
              label: 'Bio',
              hintText: 'Share a little about what matters to you.',
              maxLines: 4,
              maxLength: 500,
            ),
            Gap(Spacing.md.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Text(
                'Your profile must pass moderation and trusted age verification before activation. Photos remain unavailable until their production gate is approved.',
                style: textTheme.bodySmall,
              ),
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Activate profile',
              onPressed: _isValid && !_isLoading ? _saveAndActivate : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isLoading,
            ),
            Gap(Spacing.md.h),
            TextButton(
              onPressed:
                  _isLoading ? null : () => _showDeleteProfileConfirmation(),
              child: Text(
                'Delete saved dating profile',
                style: TextStyle(color: colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteProfileConfirmation() {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete saved dating profile?'),
            content: const Text(
              'This removes your dating profile draft and hides you from new introductions until you create a new one.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await ref.read(deleteDatingProfileProvider.future);
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dating profile deleted')),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          items:
              items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildAgePicker(
    BuildContext context, {
    required String label,
    required int value,
    required ValueChanged<int?> onChanged,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall),
        Gap(Spacing.xs.h),
        DropdownButtonFormField<int>(
          value: value,
          items: List.generate(53, (index) {
            final age = index + 18;
            return DropdownMenuItem<int>(value: age, child: Text('$age'));
          }),
          onChanged: onChanged,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ],
    );
  }
}
