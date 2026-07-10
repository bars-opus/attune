import 'package:attune/app/documentations/legal_documentation/models/documentation_item.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

class LegalDocumentationData {
  // End User License Agreement
  static DocumentationItem eula(BuildContext context) => DocumentationItem(
    id: 'eula',
    title: AppLocalizations.of(context)!.eulaTitle,
    subtitle: AppLocalizations.of(
      context,
    )!.eulaContent(AppConstants.appName, AppConstants.supportEmail),
    footerText: AppLocalizations.of(context)!.eulaFooter,
    icon: Icons.description,
    iconColor: Colors.blue,
  );
  static DocumentationItem privacyPolicy(BuildContext context) {
    return DocumentationItem(
      id: 'privacy_policy',
      title: AppLocalizations.of(context)!.privacyPolicyTitle,
      subtitle: AppLocalizations.of(
        context,
      )!.privacyPolicyContent(AppConstants.appName),
      footerText: AppLocalizations.of(context)!.privacyPolicyFooter(
        AppConstants.appName,
        DateTime.now(), // ← Pass DateTime object, NOT formatted string
      ),
      icon: Icons.privacy_tip,
      iconColor: Colors.green,
    );
  }

  static DocumentationItem termsOfService(BuildContext context) =>
      DocumentationItem(
        id: 'terms_of_service',
        title: AppLocalizations.of(context)!.termsTitle,
        subtitle: AppLocalizations.of(
          context,
        )!.termsContent(AppConstants.appName, AppConstants.supportEmail),
        footerText: '',
        icon: Icons.gavel,
        iconColor: Colors.orange,
      );

  static DocumentationItem dataSharingAgreement(BuildContext context) =>
      DocumentationItem(
        id: 'data_sharing',
        title: AppLocalizations.of(context)!.dataSharingTitle,
        subtitle: AppLocalizations.of(
          context,
        )!.dataSharingContent(AppConstants.appName),
        footerText: AppLocalizations.of(
          context,
        )!.dataSharingFooter(AppConstants.appName),
        icon: Icons.share,
        iconColor: Colors.purple,
      );

  // Get all documents
  static List<DocumentationItem> allDocuments(BuildContext context) => [
    eula(context),
    privacyPolicy(context),
    termsOfService(context),
    dataSharingAgreement(context),
  ];

  // Find document by ID
  static DocumentationItem? findById2(String id, BuildContext context) {
    final docs = allDocuments(context);
    for (final doc in docs) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  // Helper: Get multiple documents by IDs
  static List<DocumentationItem> findByIds(
    List<String> ids,
    BuildContext context,
  ) {
    final docs = allDocuments(context);
    return docs.where((doc) => ids.contains(doc.id)).toList();
  }
}
