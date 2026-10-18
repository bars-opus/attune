/// One block of a manual section. Blocks render in list order; `order` is
/// metadata only. Text and bullet blocks accept `**bold**`.
class ManualContent {
  final String id;
  final String title;
  final String content;
  final ManualContentType type;
  // final IconData? icon;
  final String? numberPrefix; // NEW: For numbered lists (e.g., "1.", "2.")
  final List<String>? bulletPoints;
  final String? codeSnippet;
  final String? imageUrl;
  final int order;

  /// For [ManualContentType.link]: the related topic it opens. [content] is
  /// the one line under the topic's title saying why to read it.
  final String? linkedModuleId;

  const ManualContent({
    required this.id,
    required this.title,
    required this.content,
    this.type = ManualContentType.text,
    // this.icon,
    this.numberPrefix, // NEW
    this.bulletPoints,
    this.codeSnippet,
    this.imageUrl,
    this.order = 0,
    this.linkedModuleId,
  });
}

// This is an ENUM - defines possible content types
enum ManualContentType {
  text, // Regular text content
  bulletList, // Bulleted list content
  code, // Code snippets
  image, // Images with captions
  warning, // Warning boxes
  tip, // Pro tip boxes
  important, // Important notice boxes
  link, // Opens a related topic in place (shown only while it is listed)
}
