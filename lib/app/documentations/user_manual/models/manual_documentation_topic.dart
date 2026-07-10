import 'package:attune/core/utils/exports/export_screens.dart';

class ManualDocumentationTopic {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<ManualSection> sections;
  final List<FAQModel> faqs;

  const ManualDocumentationTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sections,
    required this.faqs,
  });

  // Factory constructor - NOW WITH CONTEXT PARAMETER
  factory ManualDocumentationTopic.fromModule(
    DocumentationModule module,
    BuildContext context,
  ) {
    return ManualDocumentationTopic(
      title: module.getTitle(context), // ✅ Now has context
      subtitle: module.getSubtitle(
        context,
      ), // ✅ Now has context (not module.subtitle)
      icon: module.icon,
      sections: module.getSections(context), // ✅ Now has context
      faqs: module.getFAQs(context), // ✅ Now has context
    );
  }

  // Alternative: Static method with clearer naming
  static ManualDocumentationTopic createFromModule(
    DocumentationModule module,
    BuildContext context,
  ) {
    return ManualDocumentationTopic(
      title: module.getTitle(context),
      subtitle: module.getSubtitle(context),
      icon: module.icon,
      sections: module.getSections(context),
      faqs: module.getFAQs(context),
    );
  }
}
