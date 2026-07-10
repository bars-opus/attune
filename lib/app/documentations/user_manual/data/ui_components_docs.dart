import 'package:attune/core/utils/exports/export_screens.dart';

class UIComponentsDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'UI Components';

  @override
  String get id => 'ui_components';

  @override
  String getSubtitle(BuildContext context) =>
      'Ready-to-use widgets and screens for the best experience and getting the desired outcome';

  @override
  IconData get icon => Icons.widgets;

  @override
  int get order => 11;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'uiComponents',
      title: 'UI Components',
      subtitle: 'Ready-to-use widgets and screens',
      icon: Icons.widgets,
      category: 'Development',
      order: 3,
      contents: [
        // TEXT introduction
        ManualContent(
          id: 'design_system',
          title: 'Design System',
          content:
              'The template includes a comprehensive design system with tokens for spacing, colors, typography, and more.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),

        // IMAGE showing component library
        ManualContent(
          id: 'component_library',
          title: 'Component Library',
          content: 'All reusable components are documented in the storybook.',
          numberPrefix: '2',
          type: ManualContentType.image,
          imageUrl: 'assets/images/component_library.png',
        ),

        // BULLET LIST of components
        ManualContent(
          id: 'available_components',
          title: 'Available Components',
          content: 'The template includes these pre-built components:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'AppButton: Customizable button with multiple variants',
            'AppTextField: Text input with validation and error states',
            'AppCard: Consistent card widget with elevation',
            'AppDialog: Modal dialogs and bottom sheets',
            'AppLoader: Loading indicators and skeletons',
            'AppTabBar: Custom tab navigation',
          ],
        ),

        // CODE for using a component
        ManualContent(
          id: 'button_usage',
          title: 'Using AppButton',
          content: 'Here\'s how to use the AppButton component:',
          numberPrefix: '4',
          type: ManualContentType.code,
          codeSnippet: '''
AppButton(
  label: 'Submit',
  onPressed: () {
    // Handle button press
  },
  variant: AppButtonVariant.primary,
  size: AppButtonSize.large,
  isLoading: false,
  isDisabled: false,
  icon: Icons.send,
)
        ''',
        ),

        // IMPORTANT note about customization
        ManualContent(
          id: 'customization_important',
          title: '',
          content:
              'You can customize all components by modifying the design tokens. Don\'t edit component source directly.',
          type: ManualContentType.important,
        ),

        // TIP for component development
        ManualContent(
          id: 'component_tip',
          title: '',
          content:
              'When creating new components, always include documentation and test cases in the same PR.',
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
