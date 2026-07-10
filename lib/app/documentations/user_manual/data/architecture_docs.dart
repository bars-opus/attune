import 'package:attune/core/utils/exports/export_screens.dart';

class ArchitectureDocs implements DocumentationModule {
  @override
  int get order => 7;

  @override
  String getTitle(BuildContext context) => 'Architecture';

  @override
  String get id => 'architecture';

  @override
  String getSubtitle(BuildContext context) =>
      'Project structure, patterns & design decisions that shapens the future and present';

  @override
  IconData get icon => Icons.architecture;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'architecture',
      title: 'Architecture',
      subtitle:
          'Understanding the project structure. \nFollows the Clean Architecture principles with clear separation between presentation, domain, and data layers.',
      icon: Icons.architecture,
      category: 'Development',
      order: 2,
      contents: [
        // BULLET LIST with specific points
        ManualContent(
          id: 'architecture_layers',
          title: 'Project Layers',
          content: 'The project is organized into these layers:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Presentation: UI components, widgets, and screens',
            'Domain: Business logic, entities, and use cases',
            'Data: APIs, databases, and repositories',
            'Core: Shared utilities, constants, and helpers',
          ],
        ),

        // CODE snippet for repository pattern
        ManualContent(
          id: 'repository_example',
          title: 'Repository Implementation',
          content:
              'Here\'s an example of a repository using the interface pattern:',
          numberPrefix: '2',
          type: ManualContentType.code,
          codeSnippet: '''
abstract class UserRepository {
  Future<User> getUser(String id);
  Future<void> saveUser(User user);
  Future<void> deleteUser(String id);
}

class UserRepositoryImpl implements UserRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;
  
  UserRepositoryImpl(this._apiClient, this._localStorage);
  
  Future<User> getUser(String id) async {
    try {
      return await _apiClient.getUser(id);
    } catch (e) {
      final localUser = await _localStorage.getUser(id);
      if (localUser != null) return localUser;
      rethrow;
    }
  }
}
        ''',
        ),

        // WARNING about state management
        ManualContent(
          id: 'state_warning',
          title: '',
          content:
              'Avoid putting business logic directly in widgets. Always use controllers or providers to manage state.',
          type: ManualContentType.warning,
        ),

        // TIP for testing
        ManualContent(
          id: 'testing_tip',
          title: '',
          content:
              'Write tests for your use cases first, then implement the UI. This ensures your business logic is solid.',
          type: ManualContentType.tip,
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
