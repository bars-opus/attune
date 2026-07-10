import 'package:attune/core/utils/exports/export_screens.dart';

class GettingStartedDocs implements DocumentationModule {
  @override
  int get order => 9;

  @override
  String getTitle(BuildContext context) => 'Getting Started';

  @override
  String get id => 'getting Started';

  @override
  String getSubtitle(BuildContext context) =>
      'Essential steps to begin using the app. Lets launch you journey into the sky no more grounds work';

  @override
  IconData get icon => Icons.rocket_launch;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'gettingStarted',
      title: 'Getting Started',
      subtitle: 'Essential steps to begin using the app',
      icon: Icons.rocket_launch,
      category: 'Basics',
      order: 3,
      contents: [
        // 1. TEXT Type (Regular text)
        ManualContent(
          id: 'welcome_text',
          title: 'Welcome to NanoEmbryo',
          numberPrefix: '1',
          content:
              'This is a production-ready Flutter starter template designed to accelerate your mobile app development. Built with clean architecture and modern design patterns.',
          type: ManualContentType.text,
        ),

        // 2. BULLET LIST Type
        ManualContent(
          id: 'features_list',
          title: 'Key Features',
          numberPrefix: '2',
          content: 'The template includes these essential features:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Clean Architecture with proper separation of concerns',
            'State management using Riverpod',
            'Custom design system with tokens',
            'Authentication flow with Firebase',
            'Localization and theming support',
            'Unit and widget testing setup',
          ],
        ),

        // 3. CODE Type
        ManualContent(
          id: 'setup_code',
          title: 'Installation Command',
          content:
              'To get started, run the following command in your terminal:',
          numberPrefix: '3',
          type: ManualContentType.code,
          codeSnippet: '''
# Clone the repository
git clone https://github.com/your-org/nano-embryo.git

# Navigate to project
cd nano-embryo

# Install dependencies
flutter pub get

# Run the app
flutter run
        ''',
        ),

        // 4. IMAGE Type
        ManualContent(
          id: 'dashboard_image',
          title: 'Main Dashboard',
          content:
              'The main dashboard provides an overview of your app\'s key metrics.',
          numberPrefix: '4',
          type: ManualContentType.image,
          imageUrl: 'assets/images/dashboard_screenshot.png',
        ),

        // 5. WARNING Type
        ManualContent(
          id: 'api_warning',
          title: '',
          content:
              'Before deploying to production, make sure to update all API keys and secrets. Never commit sensitive credentials to version control.',
          type: ManualContentType.warning,
        ),

        // 6. TIP Type
        ManualContent(
          id: 'development_tip',
          title: '',
          content:
              'Use the included scripts folder for common tasks like building APKs/IPAs, running tests, or generating code.',
          type: ManualContentType.tip,
        ),

        // 7. IMPORTANT Type
        ManualContent(
          id: 'licensing_important',
          title: '',
          content:
              'This template is licensed under MIT. You can use it for commercial projects, but attribution is appreciated.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_getting_started_1',
        question: 'How do I install the template?',
        answer: 'Clone the repository and run flutter pub get...',
        category: 'Getting Started',

        order: 1,
      ),
      FAQModel(
        id: 'faq_getting_started_2',
        question: 'What are the system requirements?',
        answer: 'Flutter 3.0+, Dart 2.17+, and a code editor...',
        category: 'Getting Started',
        order: 2,
      ),
    ];
  }
}
