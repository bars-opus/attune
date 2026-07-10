// lib/features/documentation/presentation/widgets/documentation_tab_view.dart
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class DocumentationTabView extends StatefulWidget {
  final List<ManualSection> documentation;
  final List<FAQModel> faqs;
  final bool showDocumentationFirst;

  const DocumentationTabView({
    super.key,
    required this.documentation,
    required this.faqs,
    this.showDocumentationFirst = true,
  });

  @override
  State<DocumentationTabView> createState() => _DocumentationTabViewState();
}

class _DocumentationTabViewState extends State<DocumentationTabView> {
  @override
  Widget build(BuildContext context) {
    final tabs = [
      AppTabItem(
        label: 'Documentation',
        icon: Icons.article,
        content: ManualWidget(sections: widget.documentation),
      ),
      AppTabItem(
        label: 'FAQs',
        icon: Icons.help_outline,
        content: FAQWidget(faqs: widget.faqs),
      ),
    ];

    return TabsWithContent(
      useNestedScrollMode: true,
      tabs: widget.showDocumentationFirst ? tabs : tabs.reversed.toList(),
      initialIndex: 0,
      scrollable: false,
      showContent: true,
    );
  }
}
