enum OnboardingMode { personal, couplesPending, couples }

extension OnboardingModeLabel on OnboardingMode {
  String get label {
    switch (this) {
      case OnboardingMode.personal:
        return 'Single';
      case OnboardingMode.couplesPending:
        return 'Waiting for partner';
      case OnboardingMode.couples:
        return 'In a relationship';
    }
  }

  bool get isRelationshipTrack {
    return this == OnboardingMode.couples ||
        this == OnboardingMode.couplesPending;
  }

  String get remoteModeName {
    return this == OnboardingMode.personal ? 'personal' : 'couples';
  }
}

class OnboardingQuestion {
  const OnboardingQuestion(this.prompt);

  final String prompt;
}

const attachmentQuestions = <OnboardingQuestion>[
  OnboardingQuestion('I find it easy to ask for reassurance when I need it.'),
  OnboardingQuestion('I worry that people I love may pull away.'),
  OnboardingQuestion('I prefer solving emotional problems by myself first.'),
  OnboardingQuestion('I can stay calm during difficult conversations.'),
  OnboardingQuestion('I notice small changes in someone else\'s tone quickly.'),
  OnboardingQuestion('I need space before I can explain what I feel.'),
  OnboardingQuestion('I feel safe depending on someone close to me.'),
  OnboardingQuestion(
    'Conflict often makes me fear the relationship is at risk.',
  ),
  OnboardingQuestion('I sometimes shut down when emotions get intense.'),
  OnboardingQuestion(
    'I can name what I need without blaming the other person.',
  ),
  OnboardingQuestion('I feel uneasy when a partner needs too much closeness.'),
  OnboardingQuestion('I replay conversations long after they happen.'),
  OnboardingQuestion('I trust that repair is possible after disagreement.'),
  OnboardingQuestion('I often need proof that someone still cares.'),
  OnboardingQuestion('I avoid sharing needs that might inconvenience someone.'),
  OnboardingQuestion('I can receive feedback without feeling attacked.'),
  OnboardingQuestion('I become more distant when I feel misunderstood.'),
  OnboardingQuestion('I know the difference between a request and a demand.'),
  OnboardingQuestion('I feel grounded when a partner has their own life.'),
  OnboardingQuestion('I find silence from someone close hard to tolerate.'),
  OnboardingQuestion('I can apologize without losing my sense of self.'),
  OnboardingQuestion('I sometimes test whether someone really cares.'),
  OnboardingQuestion('I need emotional independence to feel safe.'),
  OnboardingQuestion('I can describe my relationship patterns clearly.'),
  OnboardingQuestion(
    'I believe closeness can be steady without being perfect.',
  ),
];

const personalAnchorPrompts = <String>[
  'What do you most want to understand about yourself in relationships?',
  'What pattern from past relationships are you trying to do differently?',
  'What does a steady relationship feel like to you?',
];

const relationshipAnchorPrompts = <String>[
  'What\'s one thing you genuinely admire about your partner?',
  'What\'s one thing you\'re hoping this relationship gives you more of?',
  'What\'s one pattern from past relationships you\'re trying to do differently?',
];
