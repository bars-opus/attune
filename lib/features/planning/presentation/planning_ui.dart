import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/app_colors.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/confirmation_dialog.dart';
import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
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

/// The solid fill behind a category's icon, under an icon in the theme's
/// background colour. Used for the category rows, the gallery ideas and
/// the colour picker, so a new category looks the way it will on the list.
///
/// Dark mode: the colour's primary tone. Light mode: the app colour itself
/// (bright), deepened toward the primary tone only as far as the white
/// icon needs to stay readable (3:1) — so orange and amber deepen a
/// little, the rest stay as they are.
Color planningCategoryFill(BuildContext context, String token) {
  final theme = Theme.of(context);
  final deep = _scheme(token, theme.brightness).primary;
  if (theme.brightness == Brightness.dark) return deep;
  final icon = theme.colorScheme.background; // ignore: deprecated_member_use
  final seed = _seeds[token] ?? LightColors.grey;
  for (var t = 0.0; t <= 1.0; t += 0.05) {
    final c = Color.lerp(seed, deep, t)!;
    if (_contrast(c, icon) >= 3.0) return c;
  }
  return deep;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
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
  context.showErrorSnackbar(planningErrorMessage(e));
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

/// Asks for one line of text in the app's sheet ([BottomSheetUtils], with
/// its header). Done saves; with a [validator], an entry it refuses keeps the
/// sheet open with the reason under the field. Null when dismissed, or when
/// left empty unless [allowEmpty].
Future<String?> askPlanningText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  int maxLength = 80,
  TextInputType? keyboardType,
  String? hint,
  bool allowEmpty = false,
  String? Function(String value)? validator,
}) =>
    BottomSheetUtils.showDocumentationBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: _PlanningTextSheet(
        title: title,
        label: label,
        initial: initial,
        maxLength: maxLength,
        keyboardType: keyboardType,
        hint: hint,
        validator: validator,
      ),
    ).then((v) => v == null || (v.isEmpty && !allowEmpty) ? null : v);

/// Owns its controller, so it lives exactly as long as the sheet's route
/// (including the closing animation).
class _PlanningTextSheet extends StatefulWidget {
  const _PlanningTextSheet({
    required this.title,
    required this.label,
    required this.initial,
    required this.maxLength,
    required this.keyboardType,
    required this.hint,
    required this.validator,
  });
  final String title;
  final String label;
  final String initial;
  final int maxLength;
  final TextInputType? keyboardType;
  final String? hint;
  final String? Function(String value)? validator;

  @override
  State<_PlanningTextSheet> createState() => _PlanningTextSheetState();
}

class _PlanningTextSheetState extends State<_PlanningTextSheet> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final value = _c.text.trim();
    final error = value.isEmpty ? null : widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    popPlanningSheet(context, value);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BottomSheetHeader(title: widget.title, onPressed: _done),
          AppTextFormField(
            controller: _c,
            autofocus: true,
            keyboardType: widget.keyboardType ?? TextInputType.text,
            label: widget.label,
            labelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            hintText: widget.hint,
            errorText: _error,
            textInputAction: TextInputAction.done,
            inputFormatters: [CodePointLengthFormatter(widget.maxLength)],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onFieldSubmitted: (_) => _done(),
          ),
        ],
      );
}

/// Closes the sheet [context] is in, with [result], once. Done can fire
/// twice (a double tap, or the keyboard's Done and the header's together);
/// popping again would close the note underneath instead.
void popPlanningSheet<T>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop<T>(result);
}

/// Why [value] is not a web address Planning can link to; null when it is.
String? planningUrlError(String value) =>
    normalizePlanningUrl(value) == null ? 'Enter a web address, like airbnb.com/rooms/1' : null;

/// "villa.example/ubud" -> "https://villa.example/ubud". Null unless the
/// result is an http(s) address with a dotted host (the server re-checks).
String? normalizePlanningUrl(String input) {
  final t = input.trim();
  if (t.isEmpty || t.length > 2048 || t.contains(RegExp(r'\s'))) return null;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t) ? t : 'https://$t';
  final u = Uri.tryParse(withScheme);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || !u.host.contains('.')) return null;
  return withScheme;
}

String planningMemberName(List<PlanningMember> members, String? id) {
  for (final m in members) {
    if (m.id == id) return m.displayName.isEmpty ? 'Partner' : m.displayName;
  }
  return 'Someone';
}

/// Where a Planning push opens: its relationship and plan, or null if the
/// payload is incomplete.
({String relationshipId, String entryId})? planningEntryTarget(Map<String, dynamic>? data) {
  final rel = data?['relationship_id'];
  final entry = data?['entry_id'];
  if (rel is! String || entry is! String || rel.isEmpty || entry.isEmpty) return null;
  return (relationshipId: rel, entryId: entry);
}

/// Shown when a Planning route opens without its plan (e.g. after the app
/// was restored without the push's data). Always offers a way back.
class PlanningUnavailableScreen extends StatelessWidget {
  const PlanningUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Planning')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Planning unavailable.'),
            const Gap(Spacing.sm),
            TextButton(
              onPressed: () async {
                if (!await Navigator.of(context).maybePop() && context.mounted) GoRouter.maybeOf(context)?.go('/home');
              },
              child: const Text('Go back'),
            ),
          ]),
        ),
      );
}

/// Apple Notes-style groups by last activity: Today, Yesterday, Previous 7
/// Days, Previous 30 Days, then month names this year, then years. Groups
/// come out newest first; plans keep their order within a group.
List<({String title, List<PlanningEntrySummary> entries})> planningDateSections(
    List<PlanningEntrySummary> entries, DateTime now) {
  final today = DateUtils.dateOnly(now);
  String bucket(DateTime at) {
    final day = DateUtils.dateOnly(at.toLocal());
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days <= 7) return 'Previous 7 Days';
    if (days <= 30) return 'Previous 30 Days';
    if (day.year == today.year) return DateFormat.MMMM().format(day);
    return '${day.year}';
  }

  final groups = <String, List<PlanningEntrySummary>>{};
  final newest = <String, DateTime>{};
  for (final e in entries) {
    final key = bucket(e.lastActivityAt);
    (groups[key] ??= []).add(e);
    final at = e.lastActivityAt;
    if (newest[key] == null || at.isAfter(newest[key]!)) newest[key] = at;
  }
  final keys = groups.keys.toList()..sort((a, b) => newest[b]!.compareTo(newest[a]!));
  return [for (final k in keys) (title: k, entries: groups[k]!)];
}

/// The date on a plan row: the time today, "Yesterday", the weekday this
/// week, else the short date.
String planningRowDate(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(local)).inDays;
  if (days <= 0) return DateFormat.jm().format(local);
  if (days == 1) return 'Yesterday';
  if (days <= 7) return DateFormat.EEEE().format(local);
  return DateFormat.yMd().format(local);
}

String planningCategoryHeroTag(String categoryId) => 'planning-category-title-$categoryId';

/// A category's name in an app bar. The category list and the plans in it
/// both show it, in this one style, so it flies between them (a Hero)
/// instead of jumping when a plan opens or closes.
class PlanningCategoryTitle extends StatelessWidget {
  const PlanningCategoryTitle({super.key, required this.categoryId, required this.name});
  final String categoryId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Hero(
      tag: planningCategoryHeroTag(categoryId),
      // Material keeps the text styled while it flies (no underline flash).
      child: Material(
        type: MaterialType.transparency,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

/// Planning's single-date picker: the app's Cupertino wheel, in the app sheet.
///
/// Resolves to the date the wheel shows when the sheet closes ([initial], or
/// today, if it was never turned), so closing it is choosing. [onChanged]
/// sees every turn, for a row that updates live behind the sheet.
Future<DateTime> pickPlanningDate(
  BuildContext context, {
  DateTime? initial,
  ValueChanged<DateTime>? onChanged,
}) async {
  final now = DateTime.now();
  var shown = DateUtils.dateOnly(initial ?? now);
  final min = DateTime(now.year - 5);
  final max = DateTime(now.year + 10, 12, 31);
  await showCupertinoDateTimeSheet(
    context: context,
    mode: CupertinoDatePickerMode.date,
    initialDateTime: shown,
    // A saved date outside the usual window still opens on itself.
    minimumDate: shown.isBefore(min) ? shown : min,
    maximumDate: shown.isAfter(max) ? shown : max,
    sheetHeight: 350.h,
    onChanged: (d) {
      shown = DateUtils.dateOnly(d);
      onChanged?.call(shown);
    },
  );
  return shown;
}
