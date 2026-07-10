import 'package:attune/core/utils/exports/export_screens.dart';

class DashboardDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) =>
      AppLocalizations.of(context)!.dashboardTitle;

  @override
  String get id => 'dashboard';

  @override
  String getSubtitle(BuildContext context) =>
      AppLocalizations.of(context)!.dashboardSubtitle;

  @override
  IconData get icon => Icons.dashboard;

  @override
  int get order => 8;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'dashboard',
      title: AppLocalizations.of(context)!.dashboardSectionTitle,
      subtitle: AppLocalizations.of(context)!.dashboardSectionSubtitle,
      icon: Icons.dashboard,
      category: AppLocalizations.of(context)!.categoryFeatures,
      order: 2,
      contents: [
        ManualContent(
          id: 'dashboard_payout',
          title: AppLocalizations.of(context)!.dashboardPayoutTitle,
          numberPrefix: '1',
          content: AppLocalizations.of(context)!.dashboardPayoutContent,
          type: ManualContentType.bulletList,
        ),
        ManualContent(
          id: 'dashboard_analytics',
          title: AppLocalizations.of(context)!.dashboardAnalyticsTitle,
          numberPrefix: '2',
          content: AppLocalizations.of(context)!.dashboardAnalyticsContent,
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dashboard_screenshot',
          title: AppLocalizations.of(context)!.dashboardScreenshotTitle,
          content: AppLocalizations.of(context)!.dashboardScreenshotContent,
          numberPrefix: '3',
          type: ManualContentType.image,
          imageUrl: 'https://your-cdn.com/images/dashboard-overview.png',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_dashboard_1',
        question: AppLocalizations.of(context)!.faqDashboard1Question,
        answer: AppLocalizations.of(context)!.faqDashboard1Answer,
        category: AppLocalizations.of(context)!.categoryDashboard,
        order: 1,
      ),
      FAQModel(
        id: 'faq_dashboard_2',
        question: AppLocalizations.of(context)!.faqDashboard2Question,
        answer: AppLocalizations.of(context)!.faqDashboard2Answer,
        category: AppLocalizations.of(context)!.categoryDashboard,
        order: 2,
      ),
    ];
  }
}
