import 'package:attune/app/theme/app_theme.dart' show ColorSchemeExtension;
import 'package:gap/gap.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/planning_models.dart';
import '../planning_ui.dart';
import 'block_tool_tray.dart';
import 'planning_doc_scope.dart';
import 'planning_quill.dart';

/// The plan's ribbon, docked above the keyboard like a word processor's:
/// Home formats the text the cursor is in; Insert adds a block where the
/// cursor is.
class PlanningRibbon extends StatefulWidget {
  const PlanningRibbon({super.key, required this.onInsert, this.tools = planningBlockTools});
  final ValueChanged<PlanningBlockType> onInsert;

  /// What Insert offers (Planning: every block; the journal: text and photo).
  final List<(PlanningBlockType, IconData, String)> tools;

  /// Highlight and text-colour tokens (spec §6.1): the only colours applied.
  static const tokens = ['yellow', 'green', 'blue', 'pink', 'purple'];

  @override
  State<PlanningRibbon> createState() => _PlanningRibbonState();
}

class _PlanningRibbonState extends State<PlanningRibbon> {
  bool _insert = false;

  /// Every ribbon sheet spans the screen, even when its choices don't
  /// fill a row (Material 3 otherwise stops sheets at 640 wide).
  static const _fullWidth = BoxConstraints(maxWidth: double.infinity);

  Future<void> _pickToken(QuillController controller, {required bool background}) async {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final kind = background ? 'Highlight' : 'Text';
    Widget swatch(BuildContext c, {required String tooltip, required String value, required Widget circle}) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.pop(c, value),
            child: SizedBox.square(dimension: 48, child: Center(child: circle)),
          ),
        );
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: _fullWidth,
      builder: (c) => SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
            child: Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
              // No colour: clears it, as a swatch rather than a text button.
              swatch(c,
                  tooltip: background ? 'No highlight' : 'Default text colour',
                  value: '',
                  circle: CircleAvatar(
                    radius: 16,
                    // The app's neutral, so it stands apart from the sheet behind it.
                    backgroundColor: scheme.neutral,
                    child: Icon(Icons.format_color_reset_rounded, size: 18, color: scheme.onSurfaceVariant),
                  )),
              for (final t in PlanningRibbon.tokens)
                swatch(c,
                    tooltip: '$kind $t',
                    value: t,
                    circle: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          background ? planningHighlightPalette(brightness)[t] : planningTextTone(t, brightness),
                    )),
            ]),
          ),
        ),
      ),
    );
    if (picked == null) return;
    final value = picked.isEmpty ? null : picked;
    controller.formatSelection(background ? BackgroundAttribute(value) : ColorAttribute(value));
  }

  /// Choices open in a bottom sheet, like the colours: the keyboard steps
  /// aside while you pick and comes back after. (A dropdown would open
  /// under the keyboard, since the ribbon sits right on top of it.)
  Future<void> _pickOption(
    QuillController controller, {
    required String title,
    required List<(String, Attribute, TextStyle?)> options,
    required Object? current,
    void Function(Attribute picked)? apply,
  }) async {
    final picked = await showModalBottomSheet<Attribute>(
      context: context,
      showDragHandle: true,
      constraints: _fullWidth,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
            child: Text(title, style: Theme.of(c).textTheme.titleMedium),
          ),
          for (final (label, attribute, style) in options)
            ListTile(
              title: Text(label, style: style),
              trailing: attribute.value == current ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(c, attribute),
            ),
        ]),
      ),
    );
    if (picked != null) (apply ?? controller.formatSelection)(picked);
  }

  Future<void> _pickHeading(QuillController controller) {
    final text = Theme.of(context).textTheme;
    return _pickOption(controller,
        title: 'Paragraph style',
        current: controller.getSelectionStyle().attributes[Attribute.header.key]?.value,
        // A heading clears the text sizes in its line (they'd only shrink it).
        apply: (picked) => planningApplyHeading(controller, picked),
        options: [
          ('Normal text', Attribute.clone(Attribute.header, null), text.bodyLarge),
          ('Heading 1', Attribute.h1, text.headlineSmall),
          ('Heading 2', Attribute.h2, text.titleLarge),
          ('Heading 3', Attribute.h3, text.titleMedium),
        ]);
  }

  Future<void> _pickSize(QuillController controller) async {
    // A heading has its own size; sizes are for normal text.
    if (!planningSizeAllowed(controller)) {
      context.showInfoSnackbar('Headings have their own size. Choose Normal text in Heading to size it.');
      return;
    }
    final body = Theme.of(context).textTheme.bodyLarge;
    TextStyle? at(String size) => body?.copyWith(fontSize: planningTextSizes[size]);
    return _pickOption(controller,
        title: 'Text size',
        current: controller.getSelectionStyle().attributes[Attribute.size.key]?.value,
        options: [
          // Named sizes the server accepts; Normal clears the size. Each
          // previews the size a note really uses.
          ('Small', const SizeAttribute('small'), at('small')),
          ('Normal', Attribute.clone(Attribute.size, null), at('normal')),
          ('Large', const SizeAttribute('large'), at('large')),
          ('Huge', const SizeAttribute('huge'), at('huge')),
        ]);
  }

  Widget _home(BuildContext context, PlanningActiveText? active) {
    if (active == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Tap into text to format it', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
      );
    }
    return planningQuillScope(
      context,
      QuillSimpleToolbar(
        controller: active.controller,
        config: QuillSimpleToolbarConfig(
          multiRowsDisplay: false,
          showFontFamily: false,
          showFontSize: false, // a sheet instead (see _pickSize)
          showHeaderStyle: false, // a sheet instead (see _pickHeading)
          showSmallButton: false,
          showLineHeightButton: false,
          showInlineCode: false,
          showColorButton: false,
          showBackgroundColorButton: false,
          showListCheck: false,
          showCodeBlock: false,
          showIndent: false,
          showDirection: false,
          showSearchButton: false,
          showSubscript: false,
          showSuperscript: false,
          showLeftAlignment: false,
          showClipboardCut: false,
          showClipboardCopy: false,
          showClipboardPaste: false,
          showUndo: false,
          showRedo: false,
          customButtons: [
            QuillToolbarCustomButtonOptions(
              icon: const Tooltip(message: 'Heading', child: Icon(Icons.title_rounded)),
              onPressed: () => _pickHeading(active.controller),
            ),
            QuillToolbarCustomButtonOptions(
              icon: const Tooltip(message: 'Text size', child: Icon(Icons.format_size_rounded)),
              onPressed: () => _pickSize(active.controller),
            ),
            QuillToolbarCustomButtonOptions(
              icon: const Tooltip(message: 'Highlight', child: Icon(Icons.format_color_fill_rounded)),
              onPressed: () => _pickToken(active.controller, background: true),
            ),
            QuillToolbarCustomButtonOptions(
              icon: const Tooltip(message: 'Text colour', child: Icon(Icons.format_color_text_rounded)),
              onPressed: () => _pickToken(active.controller, background: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inserts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Every tool is built (not lazily), so all 13 are reachable by
    // assistive technology without scrolling first.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: Row(children: [
        for (final (type, icon, label) in widget.tools)
          InkWell(
            borderRadius: BorderRadiusTokens.smAll,
            onTap: () => widget.onInsert(type),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 22, color: scheme.primary),
                  const Gap(2),
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = PlanningDocScope.maybeOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Divider(height: 1),
          Row(children: [
            for (final (insert, label) in [(false, 'Home'), (true, 'Insert')])
              Padding(
                padding: const EdgeInsets.only(left: Spacing.sm),
                child: Semantics(
                  selected: _insert == insert,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _insert == insert ? scheme.primary : scheme.onSurfaceVariant,
                      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: _insert == insert ? FontWeight.w700 : FontWeight.w500),
                    ),
                    onPressed: () => setState(() => _insert = insert),
                    child: Text(label),
                  ),
                ),
              ),
          ]),
          SizedBox(height: 56, child: _insert ? _inserts(context) : _home(context, doc?.active)),
        ]),
      ),
    );
  }
}
