// lib/features/documentation/documentation_screen.dart
// import 'package:attune/core/utils/exports/export_screens.dart';

import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

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

/// The bare list of documentation modules, with no Scaffold/AppBar of its
/// own — safe to embed directly inside a bottom sheet or any other host.
class DocumentationList extends StatelessWidget {
  const DocumentationList({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Get all modules from registry
    DocumentationRegistry.initialize();
    final modules = DocumentationRegistry.getAllModules();

    return ListView(
      children: [
        // Generate rows automatically from all modules
        ...modules.map(
          (module) => Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xs.h),
            child: InfoRowWidget(
              title: module.getTitle(context),
              subtitle: module.getSubtitle(context),
              icon: module.icon,
              trailing: Icon(
                Icons.expand_more,
                size: IconSizes.md.h,
                color: colorScheme.onBackground.withOpacity(0.3),
              ),
              avatarRadius: 25.h,
              onTap: () {
                BottomSheetUtils.showDocumentationBottomSheet(
                  context: context,
                  showButtons: false,
                  widget: DocumentationTabView(
                    documentation: module.getSections(context),
                    faqs: module.getFAQs(context),
                    showDocumentationFirst: true,
                  ),
                );
              },
              showTrailingArrow: true,
            ),
          ),
        ),
      ],
    );
  }
}
