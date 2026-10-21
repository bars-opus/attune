import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../planning_ui.dart';

/// Quill needs its own localizations. Scoped here so the app-wide
/// MaterialApp (lib/app/app.dart) is not touched.
Widget planningQuillScope(BuildContext context, Widget child) => Localizations.override(
      context: context,
      delegates: const [FlutterQuillLocalizations.delegate],
      child: child,
    );

/// Token colours: highlights via the palette Quill consults first;
/// text colours via customStyleBuilder (merged after Quill's own style).
///
/// [editable]: a text block edited in place on the plan's page — it grows
/// with its text inside the page's own scroll, and shows its cursor.
QuillEditorConfig planningQuillEditorConfig(BuildContext context,
    {String? placeholder, bool expands = false, bool editable = false}) {
  final brightness = Theme.of(context).brightness;
  return QuillEditorConfig(
    placeholder: placeholder,
    expands: expands,
    scrollable: expands,
    padding: expands ? Spacing.allMd : EdgeInsets.zero,
    showCursor: expands || editable,
    // The named sizes, as the size menu shows them (Quill's own were 10 /
    // 18 / 22 around a 16 normal).
    customStyles: DefaultStyles(
      palette: planningHighlightPalette(brightness),
      sizeSmall: TextStyle(fontSize: planningTextSizes['small']),
      sizeLarge: TextStyle(fontSize: planningTextSizes['large']),
      sizeHuge: TextStyle(fontSize: planningTextSizes['huge']),
    ),
    customStyleBuilder: (attribute) => attribute.key == Attribute.color.key && attribute.value is String
        ? TextStyle(color: planningTextTone(attribute.value as String, brightness))
        : const TextStyle(),
  );
}

/// The text sizes a note uses, by name ('normal' is no size at all): the
/// size menu previews exactly these.
const planningTextSizes = {'small': 14.0, 'normal': 16.0, 'large': 20.0, 'huge': 26.0};

/// Sizes are plain-text sizes: a heading has its own, and a fixed size on it
/// only shrank it ("Large" 18 on a 30 Heading 2). So no size menu while the
/// cursor is in a heading line.
bool planningSizeAllowed(QuillController controller) =>
    controller.getSelectionStyle().attributes[Attribute.header.key]?.value == null;

/// Applies [heading] (or Normal text) to the selected lines; a heading also
/// clears any text sizes in those lines, which a heading would shrink.
void planningApplyHeading(QuillController controller, Attribute heading) {
  final selection = controller.selection;
  controller.formatSelection(heading);
  if (heading.value == null) return;
  final doc = controller.document;
  final first = doc.queryChild(selection.start).node;
  final last = doc.queryChild(selection.end).node;
  if (first == null || last == null) return;
  final start = first.documentOffset;
  final end = last.documentOffset + last.length - 1; // up to its newline
  if (end > start) {
    controller.formatText(start, end - start, Attribute.clone(Attribute.size, null));
  }
  controller.updateSelection(selection, ChangeSource.local);
}

