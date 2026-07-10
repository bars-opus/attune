// lib/features/settings/data/settings_data.dart

// lib/features/profile/data/profile_form_data.dart
import 'package:attune/features/auth/utility/auth_exports.dart';

class ProfileFormData {
  static List<FormFieldConfig> getProfileFields(BuildContext context) {
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    return [
      FormFieldConfig(
        id: 'name',
        title: loc.editProfileNameFieldTitle,
        label: loc.editProfileNameFieldLabel,
        icon: Icons.person_outline,
        iconColor: Colors.blue,
        order: 1,
        maxLines: 1,
        keyboardType: TextInputType.name,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Name is required';
          }
          return null;
        },
      ),
      FormFieldConfig(
        id: 'userName',
        title: loc.editProfileUserFieldNameTitle,
        label: loc.editProfileUsernameFieldLabel,
        icon: Icons.alternate_email,
        iconColor: Colors.purple,
        order: 2,
        maxLines: 1,
        keyboardType: TextInputType.text,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Username is required';
          }
          if (value.contains(' ')) {
            return 'No spaces allowed';
          }
          return null;
        },
      ),
      FormFieldConfig(
        id: 'bio',
        title: loc.editProfileBioFieldTitle,
        label: loc.editProfileBioFieldLabel,
        icon: Icons.description_outlined,
        iconColor: Colors.green,
        order: 3,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        validator: (value) {
          if (value != null && value.length > 200) {
            return 'Bio must be less than 200 characters';
          }
          return null;
        },
      ),
    ];
  }
}

class FormFieldConfig {
  final String id;
  final String title;
  final String label;
  final IconData icon;
  final Color iconColor;
  final int order;
  final int? maxLines;
  final TextInputType keyboardType;
  final FormFieldValidator<String>? validator;

  const FormFieldConfig({
    required this.id,
    required this.title,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.order,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });
}
