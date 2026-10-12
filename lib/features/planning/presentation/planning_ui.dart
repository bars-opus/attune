import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/confirmation_dialog.dart';
import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/planning_error.dart';
import '../data/planning_models.dart';
import '../domain/code_point_limit.dart';

/// Must equal `planning_v2_icons()` / `planning_v2_colors()` in migration
/// 20261012200100 (a test parses the SQL and compares).
const List<String> planningIconKeys = [
  'flag', 'plane', 'heart', 'home', 'cart', 'sun', 'star', 'gift', 'book',
  'dumbbell', 'utensils', 'baby', 'ring', 'box', 'music', 'paw', 'note',
];
const List<String> planningColorKeys = ['rose', 'amber', 'teal', 'indigo', 'green', 'slate', 'violet', 'orange'];

const Map<String, IconData> _icons = {
  'flag': Icons.flag_rounded, 'plane': Icons.flight_rounded, 'heart': Icons.favorite_rounded,
  'home': Icons.home_rounded, 'cart': Icons.shopping_cart_rounded, 'sun': Icons.wb_sunny_rounded,
  'star': Icons.star_rounded, 'gift': Icons.card_giftcard_rounded, 'book': Icons.menu_book_rounded,
  'dumbbell': Icons.fitness_center_rounded, 'utensils': Icons.restaurant_rounded,
  'baby': Icons.child_friendly_rounded, 'ring': Icons.diamond_rounded, 'box': Icons.inventory_2_rounded,
  'music': Icons.music_note_rounded, 'paw': Icons.pets_rounded, 'note': Icons.sticky_note_2_rounded,
};

IconData planningIcon(String key) => _icons[key] ?? Icons.folder_rounded;

/// Category and rich-text colour tokens are seeded from the app's own
/// palette (lib/app/theme/app_colors.dart) — never free-standing hex — and
/// expanded per theme brightness, so Planning matches the app in light and dark.
const Map<String, Color> _seeds = {
  'green': LightColors.primary,
  'teal': LightColors.moderate,
  'violet': LightColors.luxury,
  'purple': LightColors.luxury,
  'amber': LightColors.ultraLuxury,
  'yellow': LightColors.ultraLuxury,
  'orange': LightColors.warning,
  'rose': LightColors.error,
  'pink': LightColors.error,
  'indigo': LightColors.info,
  'blue': LightColors.info,
  'slate': LightColors.grey,
};

final Map<(String, Brightness), ColorScheme> _schemes = {};

ColorScheme _scheme(String token, Brightness brightness) => _schemes.putIfAbsent(
    (token, brightness),
    () => ColorScheme.fromSeed(seedColor: _seeds[token] ?? LightColors.grey, brightness: brightness));

/// Tonal container + on-container pair for a category colour token.
({Color container, Color onContainer}) planningTone(BuildContext context, String token) {
  final s = _scheme(token, Theme.of(context).brightness);
  return (container: s.primaryContainer, onContainer: s.onPrimaryContainer);
}

const _richTextTokens = ['yellow', 'green', 'blue', 'pink', 'purple'];

/// Rich-text highlight tokens (spec §6.1). Quill resolves `background`
/// through DefaultStyles.palette first, so tokens never become hex.
Map<String, Color> planningHighlightPalette(Brightness b) =>
    {for (final t in _richTextTokens) t: _scheme(t, b).primaryContainer};

/// Text-colour tokens: the scheme's primary tone, readable in both themes.
Color planningTextTone(String token, Brightness b) => _scheme(token, b).primary;

const planningRouteName = 'planning_flow';

/// Title a new note starts with; replaced by the note's first line on its
/// first save (Notes category only).
const planningNewNoteTitle = 'New note';

/// Every Planning screen is pushed with this name so an `inactive` failure
/// can pop the whole Planning stack in one call (spec §9: fail closed and leave).
Route<T> planningRoute<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => page, settings: const RouteSettings(name: planningRouteName));

void showPlanningError(BuildContext context, Object error) {
  final e = mapPlanningError(error);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(planningErrorMessage(e))));
  if (e is PlanningUnauthorized) {
    Navigator.of(context).popUntil((r) => r.settings.name != planningRouteName);
  }
}

/// The app's ConfirmationDialog, resolved by the dialog closing rather than
/// by its callbacks: `ConfirmationDialog.show` awaits a completer that a
/// barrier tap never completes, so a tap outside would hang the caller.
Future<bool> planningConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
  bool destructive = false,
}) async {
  var confirmed = false;
  await showDialog<void>(
    context: context,
    builder: (_) => ConfirmationDialog(
      type: destructive ? ConfirmationType.destructive : ConfirmationType.info,
      title: title,
      message: message,
      confirmText: confirmText,
      onConfirm: () => confirmed = true,
    ),
  );
  return confirmed;
}

/// A "used/max" counter in code points, for fields limited by
/// [CodePointLengthFormatter] (Flutter's built-in counter counts graphemes).
InputCounterWidgetBuilder codePointCounter(TextEditingController controller, int max) =>
    (context, {required currentLength, required isFocused, maxLength}) =>
        Text('${codePointLength(controller.text)}/$max', style: Theme.of(context).textTheme.bodySmall);

/// The single Planning line on the Conversations card.
String planningSummaryLine(PlanningSummary? summary) => switch (summary) {
      null => 'Start planning together',
      PlanningSummary(kind: PlanningSummaryKind.overdue, :final title, :final contextDate) =>
        contextDate == null ? '$title was due' : '$title was due ${DateFormat.MMMd().format(contextDate)}',
      PlanningSummary(kind: PlanningSummaryKind.upcoming, :final title, :final contextDate) =>
        contextDate == null ? title : '$title · ${DateFormat.MMMd().format(contextDate)}',
      PlanningSummary(:final title) => title,
    };

String formatPlanningRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Pick a date';
  final full = DateFormat.yMMMd();
  if (end == null || end == start) return full.format(start);
  if (start.year == end.year) return '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}, ${end.year}';
  return '${full.format(start)} – ${full.format(end)}';
}

/// The app's ErrorStateWidget with Planning's actionable copy (checklist
/// 5.1). An ended relationship offers Close, never Retry (spec §9).
class PlanningErrorState extends StatelessWidget {
  const PlanningErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = mapPlanningError(error);
    final closed = e is PlanningUnauthorized;
    return Center(
      child: ErrorStateWidget(
        type: switch (e) {
          PlanningUnauthorized() => ErrorStateType.permissionError,
          PlanningNetwork() => ErrorStateType.networkError,
          _ => ErrorStateType.genericError,
        },
        title: closed ? 'Planning is closed' : 'Could not load this',
        subtitle: planningErrorMessage(e),
        primaryActionLabel: closed ? 'Close' : 'Retry',
        onPrimaryAction: closed ? () => Navigator.of(context).maybePop() : onRetry,
      ),
    );
  }
}

/// The app's EmptyStateWidget for Planning's empty lists.
class PlanningEmptyState extends StatelessWidget {
  const PlanningEmptyState({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => EmptyStateWidget(
        type: EmptyStateType.custom,
        icon: icon,
        title: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

/// Not colour-only (spec §5): carries its own semantics node.
class PlanningNewDot extends StatelessWidget {
  const PlanningNewDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'New from your partner',
        child: Container(
          width: Spacing.sm + Spacing.xs / 2,
          height: Spacing.sm + Spacing.xs / 2,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
        ),
      );
}
