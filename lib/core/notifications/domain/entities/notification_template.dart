// lib/features/notifications/domain/entities/notification_template.dart

/// Simple template engine without external dependencies
class NotificationTemplate {
  final String id;
  final String titleTemplate;
  final String bodyTemplate;
  final Map<String, dynamic> defaultData;

  const NotificationTemplate({
    required this.id,
    required this.titleTemplate,
    required this.bodyTemplate,
    this.defaultData = const {},
  });

  /// Render title with data using simple {{variable}} replacement
  String renderTitle(Map<String, dynamic> data) {
    final merged = {...defaultData, ...data};
    return _renderTemplate(titleTemplate, merged);
  }

  /// Render body with data using simple {{variable}} replacement
  String renderBody(Map<String, dynamic> data) {
    final merged = {...defaultData, ...data};
    return _renderTemplate(bodyTemplate, merged);
  }

  /// Simple template renderer that replaces {{variable}} with values
  String _renderTemplate(String template, Map<String, dynamic> data) {
    var result = template;

    // Replace {{variable}} patterns
    for (final entry in data.entries) {
      final pattern = '{{${entry.key}}}';
      final value = entry.value.toString();
      result = result.replaceAll(pattern, value);
    }

    // Also handle {{variable.property}} for nested objects (basic support)
    final nestedPattern = RegExp(r'{{(\w+)\.(\w+)}}');
    for (final match in nestedPattern.allMatches(template)) {
      final objKey = match.group(1);
      final propKey = match.group(2);
      if (objKey != null && propKey != null) {
        final obj = data[objKey];
        if (obj is Map<String, dynamic>) {
          final value = obj[propKey]?.toString() ?? '';
          result = result.replaceAll(match.group(0)!, value);
        }
      }
    }

    return result;
  }

  /// Create from JSON (for database storage)
  factory NotificationTemplate.fromJson(Map<String, dynamic> json) {
    return NotificationTemplate(
      id: json['id'] as String,
      titleTemplate: json['title_template'] as String,
      bodyTemplate: json['body_template'] as String,
      defaultData: json['default_data'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title_template': titleTemplate,
      'body_template': bodyTemplate,
      'default_data': defaultData,
    };
  }
}
