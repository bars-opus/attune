import 'package:attune/core/utils/exports/export_screens.dart';

/// A text widget with interactive highlighted segments that support tap actions.
///
/// This widget renders a continuous text string with specific substrings highlighted
/// visually and made interactive. It's particularly useful for:
/// - Terms and conditions with clickable links
/// - Privacy policies with expandable sections
/// - Interactive tutorials or feature highlights
/// - Any text requiring inline interactive elements
///
/// ## Key Features
/// - **Inline interactivity**: Clickable text segments within continuous text flow
/// - **Visual highlighting**: Different colors, weights, and underlining for interactive parts
/// - **Dynamic processing**: Automatically handles text positioning and segmentation
/// - **Theme integration**: Uses app theme colors and typography by default
/// - **Flexible styling**: Customizable font sizes, colors, and alignment
/// - **Accessibility**: Proper text scaling and visual cues for interactivity
///
/// ## Visual Example
/// ```
/// By using this app, you agree to our [Terms of Service] and
/// [Privacy Policy]. Please review our [Cookie Policy] for more
/// information about data collection.
/// ```
/// (Where bracketed text is highlighted and clickable)
///
/// ## Technical Implementation
/// The widget processes text in three steps:
/// 1. **Position detection**: Finds highlighted substrings within the full text
/// 2. **Segmentation**: Splits text into alternating regular/highlighted segments
/// 3. **Widget construction**: Builds a `RichText` with `TextSpan` and `WidgetSpan` elements
///
/// ## Usage Example
/// ```dart
/// HighlightedText(
///   fullText: 'By continuing, you agree to our Terms and Privacy Policy.',
///   highlightedParts: [
///     HighlightedPart(
///       text: 'Terms',
///       onTap: () => showTermsModal(context),
///     ),
///     HighlightedPart(
///       text: 'Privacy Policy',
///       onTap: () => showPrivacyModal(context),
///     ),
///   ],
///   baseFontColor: Colors.grey[700],
///   highlightFontColor: Colors.blue,
///   highlightFontSize: 14,
///   textAlign: TextAlign.center,
/// )
/// ```
class HighlightedText extends StatelessWidget {
  /// The complete text string containing both regular and highlighted segments.
  ///
  /// This is the full text that will be displayed. Highlighted segments are
  /// substrings of this text that will be visually emphasized and made interactive.
  /// Example: "Accept our Terms and Privacy Policy to continue."
  final String fullText;

  /// List of text segments to highlight and make interactive.
  ///
  /// Each `HighlightedPart` specifies:
  /// - `text`: The substring to highlight (must exist within `fullText`)
  /// - `onTap`: Optional callback when the highlighted segment is tapped
  ///
  /// The list is processed in order of appearance in the text.
  /// Changed from `List<String>` to `List<HighlightedPart>` for tap support.
  final List<HighlightedPart> highlightedParts;

  /// Font size for non-highlighted (regular) text segments.
  ///
  /// Defaults to `12.sp` (12 responsive pixels using `ScreenUtil`).
  /// Use for consistent text scaling across different screen sizes.
  final double? baseFontSize;

  /// Font size for highlighted text segments.
  ///
  /// Defaults to `12.sp` (same as base font size by default).
  /// Can be larger or smaller than `baseFontSize` for visual emphasis.
  final double? highlightFontSize;

  /// Text color for non-highlighted (regular) text segments.
  ///
  /// Defaults to theme's `onBackground` color.
  /// Typically a neutral color like grey or black/white depending on theme.
  final Color? baseFontColor;

  /// Text color for highlighted text segments.
  ///
  /// Defaults to theme's `primary` color for visual prominence.
  /// Should provide sufficient contrast against the background.
  final Color? highlightFontColor;

  /// Horizontal alignment of the text within its container.
  ///
  /// Defaults to `TextAlign.start` (left-aligned for LTR languages).
  /// Use `center` for centered text like disclaimers or `justify` for paragraphs.
  final TextAlign textAlign;

  /// Creates a text widget with interactive highlighted segments.
  ///
  /// [fullText] and [highlightedParts] are required.
  /// All highlighted text segments must exist as substrings within [fullText].
  /// Text segments are processed in the order they appear in the original text.
  const HighlightedText({
    super.key,
    required this.fullText,
    required this.highlightedParts,
    this.baseFontSize,
    this.highlightFontSize,
    this.textAlign = TextAlign.start,
    this.baseFontColor,
    this.highlightFontColor,
  });

  @override
  Widget build(BuildContext context) {
    // Collection of text spans that will compose the final rich text
    final textSpans = <InlineSpan>[]; // Changed from TextSpan to InlineSpan
    
    // Working copy of the text for position tracking
    String remainingText = fullText;
    
    // Access theme for consistent styling
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Sort highlighted parts by their position in the text for sequential processing
    final sortedParts =
        highlightedParts
            .map(
              (part) => _TextPart(
                part.text,
                remainingText.indexOf(part.text), // Find position in text
                part.onTap, // Attach tap callback
              ),
            )
            .where((part) => part.position != -1) // Filter out not-found text
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position)); // Sort by position

    int currentIndex = 0; // Track current position in text

    // Process each highlighted segment
    for (final part in sortedParts) {
      // Add regular text BEFORE the highlighted segment (if any)
      if (part.position > currentIndex) {
        textSpans.add(
          TextSpan(text: remainingText.substring(currentIndex, part.position)),
        );
      }

      // Add highlighted segment as a CLICKABLE WidgetSpan (not TextSpan)
      // This enables proper gesture detection for the highlighted text
      textSpans.add(
        WidgetSpan(
          // Align with text baseline for seamless inline appearance
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: part.onTap, // Attach provided tap callback
            child: Text(
              part.text,
              style: TextStyle(
                // Highlight color (primary theme color by default)
                color: highlightFontColor ?? colorScheme.primary,
                // Highlight font size (can differ from base)
                fontSize: highlightFontSize ?? 12.sp,
                // Bold weight for visual emphasis
                fontWeight: FontWeight.w600,
                // Underline indicates interactivity (common pattern for links)
                decoration: TextDecoration.underline,
                // Underline color matches text color
                decorationColor: highlightFontColor ?? colorScheme.primary,
              ),
            ),
          ),
        ),
      );

      // Advance position pointer past this highlighted segment
      currentIndex = part.position + part.text.length;
    }

    // Add any remaining text AFTER the last highlighted segment
    if (currentIndex < remainingText.length) {
      textSpans.add(TextSpan(text: remainingText.substring(currentIndex)));
    }

    // Construct the final rich text widget
    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        // Base text style applied to all non-highlighted segments
        style: textTheme.bodyMedium!.copyWith(
          color: baseFontColor ?? colorScheme.onBackground,
          fontSize: baseFontSize ?? 12.sp,
          height: 1.5, // Improved line height for readability
        ),
        children: textSpans,
      ),
    );
  }
}

// NEW: Data model for highlighted text segments with tap support
/// Represents a text segment that should be highlighted and made interactive.
///
/// This model extends the previous string-only approach by adding an
/// optional tap callback, enabling interactive text segments within
/// continuous text flow.
class HighlightedPart {
  /// The text substring to highlight within the full text.
  ///
  /// Must exist as a substring in the parent `HighlightedText.fullText`.
  /// Case-sensitive matching is used.
  final String text;

  /// Optional callback function triggered when the highlighted segment is tapped.
  ///
  /// Typically used for:
  /// - Navigating to related screens
  /// - Showing modal dialogs or bottom sheets
  /// - Expanding/collapsing additional information
  /// - Executing actions related to the text segment
  final VoidCallback? onTap;

  /// Creates a highlighted text segment definition.
  ///
  /// [text] is required and specifies which substring to highlight.
  /// [onTap] is optional and provides interactivity for the segment.
  const HighlightedPart({required this.text, this.onTap});
}

// Updated helper class for internal text processing
/// Internal helper class for tracking text segments during processing.
///
/// Used internally by `HighlightedText` to manage:
/// - Text content and its position within the full text
/// - Associated tap callback for interactive segments
/// - Sorting and processing order
class _TextPart {
  final String text;
  final int position;
  final VoidCallback? onTap;

  _TextPart(this.text, this.position, this.onTap);
}
