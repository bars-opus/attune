import 'dart:math' as math;

// lib/features/documentation/documentation_screen.dart
// import 'package:attune/core/utils/exports/export_screens.dart';

import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_groups.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-page version — pushed as its own route (has its own Scaffold/AppBar).
/// For embedding inside a bottom sheet (BottomSheetUtils.showDocumentationBottomSheet's
/// `widget:` param already supplies the Scaffold/ScaffoldMessenger wrapper),
/// use [DocumentationList] instead — a nested Scaffold inside the sheet's
/// constrained body renders blank rather than throwing a visible error.
class DocumentationScreen extends StatelessWidget {
  const DocumentationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [AppTextButton()],
      ),
      body: const DocumentationList(),
    );
  }
}

/// The guides, grouped into sections (owner 2026-11-26), with no
/// Scaffold/AppBar of its own — safe to embed directly inside a bottom sheet
/// or any other host (it needs a bounded height).
///
/// A search field at the top (titles, subtitles and the guides' own words),
/// then the sections, each with its guides. [initiallyOpen] picks the sections that start open (null:
/// none); a closed section shows its heading and count, and opens on a tap.
/// While searching, every section with a match is open.
class DocumentationList extends ConsumerStatefulWidget {
  const DocumentationList({super.key, this.initiallyOpen});

  /// The sections open at first; null: none, every section starts closed
  /// so the first look is only the headings (owner 2026-11-26).
  final Set<DocumentationGroup>? initiallyOpen;

  @override
  ConsumerState<DocumentationList> createState() => _DocumentationListState();
}

class _DocumentationListState extends ConsumerState<DocumentationList> {
  final _search = TextEditingController();
  late final Set<DocumentationGroup> _open = {
    ...(widget.initiallyOpen ?? const <DocumentationGroup>{}),
  };
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Everything a search looks through for [module], lower case.
  String _haystack(BuildContext context, DocumentationModule module) {
    final b = StringBuffer()
      ..write(module.getTitle(context))
      ..write(' ')
      ..write(module.getSubtitle(context));
    for (final section in module.getSections(context)) {
      b
        ..write(' ')
        ..write(section.title)
        ..write(' ')
        ..write(section.subtitle ?? '');
      for (final c in section.contents) {
        b
          ..write(' ')
          ..write(c.title)
          ..write(' ')
          ..write(c.content);
        for (final point in c.bulletPoints ?? const <String>[]) {
          b
            ..write(' ')
            ..write(point);
        }
      }
    }
    return b.toString().toLowerCase();
  }

  void _openModule(DocumentationModule module) {
    BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      showButtons: false,
      widget: DocumentationTabView(module: module, showDocumentationFirst: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    DocumentationRegistry.initialize();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Topics for switched-off features stay hidden.
    final modules = DocumentationRegistry.visibleModules(
      ref.watch(documentationFlagsProvider).valueOrNull ?? const {},
    );

    final terms = _query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final searching = terms.isNotEmpty;
    final shown = searching
        ? modules.where((m) {
            final text = _haystack(context, m);
            return terms.every(text.contains);
          }).toList()
        : modules;

    final byGroup = <DocumentationGroup, List<DocumentationModule>>{};
    for (final m in shown) {
      byGroup.putIfAbsent(documentationGroupFor(m.id), () => []).add(m);
    }
    final groups = [for (final g in DocumentationGroup.values) if (byGroup[g]?.isNotEmpty ?? false) g];

    // A tap anywhere outside the field puts the keyboard away (owner
    // 2026-11-26); taps still reach the rows.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The search field (owner 2026-11-26): the theme's lighter surface on
        // the sheet's neutral background, no outline.
        Padding(
          padding: EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadiusTokens.floatingNavAll,
            ),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search the guides',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: Spacing.allLg,
                    child: Text(
                      'No guides match "$_query".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  // No controller of its own: inside the guides sheet this
                  // takes the sheet's (PrimaryScrollController), which is
                  // what lets a pull down at the top dismiss the sheet.
                  primary: true,
                  padding: EdgeInsets.only(bottom: Spacing.xl),
                  children: [
                    for (var gi = 0; gi < groups.length; gi++) ...[
                      // A hairline between sections (owner 2026-11-26).
                      if (gi > 0)
                        Padding(
                          // More room between sections (owner 2026-11-26).
                          padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: Spacing.md,
                            endIndent: Spacing.md,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      _Section(
                        key: ValueKey(groups[gi]),
                        open: searching || _open.contains(groups[gi]),
                        header: (progress) => _GroupHeader(
                          title: groups[gi].title,
                          count: byGroup[groups[gi]]!.length,
                          progress: progress,
                          onTap: searching
                              ? null
                              : () => setState(() {
                                    final g = groups[gi];
                                    _open.contains(g) ? _open.remove(g) : _open.add(g);
                                  }),
                        ),
                        rows: [
                          for (final (i, module) in byGroup[groups[gi]]!.indexed)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: Spacing.xs.h),
                              child: InfoRowWidget(
                                title: module.getTitle(context),
                                subtitle: module.getSubtitle(context),
                                icon: module.icon,
                                avatarRadius: 25.h,
                                onTap: () => _openModule(module),
                                showTrailingArrow: true,
                                // A line between guides, none after the last.
                                showDivider: i < byGroup[groups[gi]]!.length - 1,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
      ),
    );
  }
}

/// A section that opens like a drawer (owner 2026-11-26): the height
/// unrolls from the heading, and the guides cascade in after it, each one
/// a beat behind the one above, dropping a few points into place as it
/// fades up. Closing runs it back, faster: the rows lift away first, then
/// the drawer folds shut. The heading's chevron turns with a small spring
/// and its count fills in. With reduce motion it simply opens and closes.
class _Section extends StatefulWidget {
  const _Section({
    super.key,
    required this.open,
    required this.header,
    required this.rows,
  });

  final bool open;

  /// The heading, given how open the section is (0 closed .. 1 open).
  final Widget Function(Animation<double> progress) header;
  final List<Widget> rows;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 320),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(_Section old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    // Opening: the drawer unrolls over the first 70%; closing (reverse) it
    // folds over the last 70% of the way back, after the rows have lifted.
    final height = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0, 0.75, curve: Curves.easeInCubic),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header(_c),
        // Fully closed: no rows at all, so a screen reader never reads the
        // guides of a closed section.
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) => _c.isDismissed ? const SizedBox.shrink() : child!,
          child: ClipRect(
            child: SizeTransition(
              sizeFactor: height,
              axisAlignment: -1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _cascade(i, rows.length, rows[i]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Row [i] of [n]: in a beat after the one above (the whole cascade fits
  /// in the animation however many rows), dropping 10 points as it fades.
  Widget _cascade(int i, int n, Widget row) {
    final step = n <= 1 ? 0.0 : math.min(0.07, 0.45 / (n - 1));
    final start = 0.12 + step * i;
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(start, math.min(1, start + 0.5), curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.35, 1, curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: anim,
      child: row,
      builder: (context, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A section's heading: its name, how many guides (in a small pill that
/// fills in as the section opens) and a chevron that turns with a spring.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final int count;

  /// How open the section is, 0..1.
  final Animation<double> progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final turn = CurvedAnimation(parent: progress, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value.clamp(0.0, 1.0);
        return Semantics(
          header: true,
          button: onTap != null,
          expanded: t > 0.5,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Spacing.md, Spacing.lg, Spacing.md, Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  // A circle, not a pill (owner 2026-11-26): it grows with the
                  // text size and stays round.
                  Container(
                    constraints: BoxConstraints.tight(
                      Size.square(26 * MediaQuery.textScalerOf(context).scale(1)),
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color.lerp(scheme.surfaceContainerHighest, scheme.primary, t * 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Color.lerp(scheme.onSurfaceVariant, scheme.onPrimary, t),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: Spacing.sm),
                    // Drawn, not a rotated Icon: it turns inside its own
                    // fixed box, so it can't drift out of the row while the
                    // section above resizes (owner 2026-11-26).
                    SizedBox.square(
                      dimension: 24,
                      child: CustomPaint(
                        painter: _ChevronPainter(
                          angle: math.pi * turn.value,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A "v" chevron turned by [angle] about the centre of its box.
class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.angle, required this.color});

  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width * 0.25, h = size.height * 0.125;
    final cosA = math.cos(angle), sinA = math.sin(angle);
    Offset at(double x, double y) => c + Offset(x * cosA - y * sinA, x * sinA + y * cosA);
    final path = Path()
      ..moveTo(at(-w, -h).dx, at(-w, -h).dy)
      ..lineTo(at(0, h).dx, at(0, h).dy)
      ..lineTo(at(w, -h).dx, at(w, -h).dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.angle != angle || old.color != color;
}
