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
QuillEditorConfig planningQuillEditorConfig(BuildContext context, {String? placeholder, bool expands = false}) {
  final brightness = Theme.of(context).brightness;
  return QuillEditorConfig(
    placeholder: placeholder,
    expands: expands,
    scrollable: expands,
    padding: expands ? Spacing.allMd : EdgeInsets.zero,
    showCursor: expands,
    customStyles: DefaultStyles(palette: planningHighlightPalette(brightness)),
    customStyleBuilder: (attribute) => attribute.key == Attribute.color.key && attribute.value is String
        ? TextStyle(color: planningTextTone(attribute.value as String, brightness))
        : const TextStyle(),
  );
}
