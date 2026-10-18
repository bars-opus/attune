import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';

import '../planning_ui.dart';

/// One choice in [pickPlanningLink].
class PlanningLinkOption {
  const PlanningLinkOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  /// What [pickPlanningLink] resolves to; '' is fine for "none in particular".
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// What a Budget counts, a Countdown counts to, or a Progress tracks: the
/// app's sheet of rows, a divider under each but the last, a check on
/// [current]. Resolves to the chosen id, or null when dismissed.
Future<String?> pickPlanningLink(
  BuildContext context, {
  required String title,
  required List<PlanningLinkOption> options,
  required String? current,
  Key sheetKey = const ValueKey('planning-block-picker-sheet'),
}) => BottomSheetUtils.showDocumentationBottomSheet<String>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: _PlanningLinkSheet(
    key: sheetKey,
    title: title,
    options: options,
    current: current,
  ),
);

class _PlanningLinkSheet extends StatelessWidget {
  const _PlanningLinkSheet({
    super.key,
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<PlanningLinkOption> options;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BottomSheetHeader(title: title),
        for (final (i, o) in options.indexed)
          InfoRowWidget(
            icon: o.icon,
            showAvatar: false,
            iconSize: 20,
            iconColor: scheme.primary,
            title: o.title,
            subtitle: o.subtitle,
            // Between choices; none under the last.
            showDivider: i < options.length - 1,
            trailing:
                o.id == current
                    ? Icon(
                      Icons.check_rounded,
                      color: scheme.primary,
                      semanticLabel: 'Selected',
                    )
                    : const SizedBox.shrink(),
            onTap: () => popPlanningSheet(context, o.id),
          ),
      ],
    );
  }
}
