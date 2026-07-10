// lib/features/documentation/documentation_screen.dart
// import 'package:attune/core/utils/exports/export_screens.dart';

import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class DocumentationScreen extends StatelessWidget {
  const DocumentationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Get all modules from registry
    DocumentationRegistry.initialize();
    final modules = DocumentationRegistry.getAllModules();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [AppTextButton()],
      ),
      body: ListView(
        children: [
          
          
          // ✅ Generate rows automatically from all modules
          ...modules
              .map(
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
              )
              .toList(),
        ],
      ),
    );
  }
}
