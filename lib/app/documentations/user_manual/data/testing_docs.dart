import 'package:attune/core/utils/exports/export_screens.dart';

class TestingDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Testing';

  @override
  String get id => 'testing';

  @override
  String getSubtitle(BuildContext context) =>
      'Quality assurance and testing strategies';

  @override
  IconData get icon => Icons.bug_report;

  @override
  int get order => 10;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'testing',
      title: 'Testing',
      subtitle: 'Quality assurance and testing strategies proven to work under any given condtion anywhere and everywhere',
      icon: Icons.bug_report,
      category: 'Quality',
      order: 4,
      contents: [
        // TEXT overview
        ManualContent(
          id: 'testing_strategy',
          title: 'Testing Strategy',
          content:
              'The template follows a comprehensive testing strategy with three levels of testing.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),

        // BULLET LIST of test types
        ManualContent(
          id: 'test_types',
          title: 'Test Types',
          content: 'The project includes these test categories:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Unit Tests: Test business logic and pure functions',
            'Widget Tests: Test UI components in isolation',
            'Integration Tests: Test complete user flows',
            'Golden Tests: Visual regression testing',
          ],
        ),

        // CODE for a unit test
        ManualContent(
          id: 'unit_test_example',
          title: 'Unit Test Example',
          content: 'Here\'s an example of a unit test for a use case:',
          numberPrefix: '3',
          type: ManualContentType.code,
          codeSnippet: '''
test('LoginUseCase should return user on valid credentials', () async {
  // Arrange
  final mockRepo = MockAuthRepository();
  when(mockRepo.login('test@email.com', 'password123'))
    .thenAnswer((_) async => User(id: '1', email: 'test@email.com'));
  
  final useCase = LoginUseCase(mockRepo);
  
  // Act
  final result = await useCase.execute(
    LoginParams(email: 'test@email.com', password: 'password123')
  );
  
  // Assert
  expect(result.id, '1');
  expect(result.email, 'test@email.com');
  verify(mockRepo.login('test@email.com', 'password123')).called(1);
});
        ''',
        ),

        // WARNING about test data
        ManualContent(
          id: 'test_data_warning',
          title: '',
          content:
              'Never use real user data in tests. Always use mock data or test fixtures.',
          type: ManualContentType.warning,
        ),

        // TIP for test organization
        ManualContent(
          id: 'test_organization_tip',
          title: '',
          content:
              'Organize tests in the same folder structure as the code being tested for better maintainability.',
          type: ManualContentType.tip,
        ),

        // IMAGE of test results
        ManualContent(
          id: 'test_results_image',
          title: 'Test Coverage',
          content:
              'Aim for at least 80% test coverage on critical business logic.',
          numberPrefix: '4',
          type: ManualContentType.image,
          imageUrl: 'assets/images/test_coverage.png',
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
