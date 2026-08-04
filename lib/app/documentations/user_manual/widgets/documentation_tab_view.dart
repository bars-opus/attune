// lib/features/documentation/presentation/widgets/documentation_tab_view.dart
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class DocumentationTabView extends StatefulWidget {
  final DocumentationModule module;
  final bool showDocumentationFirst;

  const DocumentationTabView({
    super.key,
    required this.module,
    this.showDocumentationFirst = true,
  });

  @override
  State<DocumentationTabView> createState() => _DocumentationTabViewState();
}

class _DocumentationTabViewState extends State<DocumentationTabView> {
  late DocumentationModule _currentModule;

  /// Single slot for the parent module, not a stack — sufficient for the
  /// current one-level-only drill-down design. A future second nesting
  /// level would require replacing this with a list/stack.
  DocumentationModule? _parentModule;

  @override
  void initState() {
    super.initState();
    _currentModule = widget.module;
  }

  void _openRelated(DocumentationModule related) {
    setState(() {
      _parentModule = _currentModule;
      _currentModule = related;
    });
  }

  void _backToParent() {
    setState(() {
      _currentModule = _parentModule!;
      _parentModule = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final relatedIds = DocumentationRegistry.getRelatedModuleIds(_currentModule.id);
    final relatedModules = relatedIds
        .map((id) => DocumentationRegistry.getById(id))
        .whereType<DocumentationModule>()
        .toList();

    final tabs = [
      AppTabItem(
        label: 'Documentation',
        icon: Icons.article,
        content: ManualWidget(sections: _currentModule.getSections(context)),
      ),
      AppTabItem(
        label: 'FAQs',
        icon: Icons.help_outline,
        content: FAQWidget(faqs: _currentModule.getFAQs(context)),
      ),
      if (relatedModules.isNotEmpty)
        AppTabItem(
          label: 'Related',
          icon: Icons.apps_outlined,
          content: _RelatedModulesList(
            modules: relatedModules,
            onTap: _openRelated,
          ),
        ),
    ];

    return Column(
      children: [
        if (_parentModule != null)
          _BackToParentRow(
            parentTitle: _parentModule!.getTitle(context),
            onTap: _backToParent,
          ),
        Expanded(
          child: TabsWithContent(
            key: ValueKey(_currentModule.id),
            useNestedScrollMode: true,
            tabs: widget.showDocumentationFirst ? tabs : tabs.reversed.toList(),
            initialIndex: 0,
            scrollable: false,
            showContent: true,
          ),
        ),
      ],
    );
  }
}

class _RelatedModulesList extends StatelessWidget {
  const _RelatedModulesList({required this.modules, required this.onTap});

  final List<DocumentationModule> modules;
  final ValueChanged<DocumentationModule> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: modules.map((module) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.xs.h),
          child: InfoRowWidget(
            title: module.getTitle(context),
            subtitle: module.getSubtitle(context),
            icon: module.icon,
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: IconSizes.md.h,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            avatarRadius: 25.h,
            onTap: () => onTap(module),
            showTrailingArrow: true,
          ),
        );
      }).toList(),
    );
  }
}

class _BackToParentRow extends StatelessWidget {
  const _BackToParentRow({required this.parentTitle, required this.onTap});

  final String parentTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Back to $parentTitle',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 48.h),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.lg.w,
              vertical: Spacing.sm.h,
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: IconSizes.sm.h, color: colorScheme.primary),
                Gap(Spacing.xs.w),
                Text(
                  parentTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
