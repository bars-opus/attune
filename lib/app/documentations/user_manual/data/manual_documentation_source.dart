import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/manual_documentation_topic.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

// lib/features/documentation/data/manual_documentation_source.dart
class ManualDocumentationSource {
  // Method 1: Get a specific topic (needs context for localization)
  static ManualDocumentationTopic getTopic(
    String topicId,
    BuildContext context,
  ) {
    final module = DocumentationRegistry.getById(topicId);

    return ManualDocumentationTopic(
      title:
          module?.getTitle(context) ??
          'Unknown Topic', // Use getTitle with context
      subtitle:
          module?.getSubtitle(context) ?? '', // Use getSubtitle with context
      icon: module?.icon ?? Icons.help,
      sections: module?.getSections(context) ?? [], // Pass context
      faqs: module?.getFAQs(context) ?? [], // Pass context
    );
  }

  // Method 2: Get all topics metadata (needs context)
  static List<TopicMetadata> getAvailableTopics(BuildContext context) {
    return DocumentationRegistry.getAllModules().map((module) {
      return TopicMetadata(
        id: module.id,
        title: module.getTitle(context), // Now using getTitle with context
        subtitle: module.getSubtitle(
          context,
        ), // Now using getSubtitle with context
        icon: module.icon,
        order: module.order,
      );
    }).toList();
  }

  // Method 3: Optional - Get modules without context (for non-UI operations)
  static List<DocumentationModule> getModules() {
    return DocumentationRegistry.getAllModules();
  }
}

// Supporting model (unchanged)
class TopicMetadata {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final int order;

  const TopicMetadata({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.order,
  });
}
