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
  const OnboardingQuestion(this.prompt, {this.description});

  final String prompt;

  /// Plain-language explanation of what the item is asking about: the kind of
  /// situation it refers to and where it commonly shows up, so a user can
  /// recognise themselves in it rather than guessing at the wording.
  ///
  /// Describes the SITUATION only. It must never tell the user what an answer
  /// says about them, name an attachment style, or imply a "better" answer —
  /// scoring does that, and per ATTUNE_MASTER_SPEC the interpretive layer is
  /// clinically gated (ATTUNE_CLINICAL.md Section 12).
  final String? description;
}

// Descriptions describe the SITUATION an item refers to — never what an answer
// means about the person. See OnboardingQuestion.description.
const attachmentQuestions = <OnboardingQuestion>[
  OnboardingQuestion(
    'Do you find it easy to ask for reassurance when you need it?',
    description:
        'Their replies have been short all day and you can\'t tell why. Can you just ask "hey, are we okay?" — or does that feel too needy to say out loud?',
  ),
  OnboardingQuestion(
    'Do you worry that people you love may pull away?',
    description:
        'They\'ve been busy and a bit distant this week. Nothing is wrong that you know of, but part of you is already wondering if they\'re losing interest. How often does that worry show up?',
  ),
  OnboardingQuestion(
    'Do you prefer solving emotional problems by yourself first?',
    description:
        'Something upset you today. Do you want to sit with it alone until you\'ve figured it out — or do you want to call someone and talk it through right away?',
  ),
  OnboardingQuestion(
    'Can you stay calm during difficult conversations?',
    description:
        'You\'re in the middle of an argument about money or plans. Can you still listen and think clearly — or does your mind go hot and fast? Calm doesn\'t mean you feel nothing.',
  ),
  OnboardingQuestion(
    'Do you notice small changes in someone else\'s tone quickly?',
    description:
        'They said "fine" — but something in how they said it was different. Do you pick that up straight away, or do you usually not notice until they tell you?',
  ),
  OnboardingQuestion(
    'Do you need space before you can explain what you feel?',
    description:
        'Right after a fight they ask "what\'s wrong?" Can you answer then — or do you need an hour, or a night, before the words are even there?',
  ),
  OnboardingQuestion(
    'Do you feel safe depending on someone close to you?',
    description:
        'You\'re sick, or having a rough week, and you need help. How comfortable is it to lean on someone — not whether you could cope alone, but whether relying on them feels safe?',
  ),
  OnboardingQuestion(
    'Does conflict often make you fear the relationship is at risk?',
    description:
        'You\'re arguing about something small. For some people it\'s just an argument. For others, a voice in the back of their mind is asking "is this it — are we breaking up?"',
  ),
  OnboardingQuestion(
    'Do you sometimes shut down when emotions get intense?',
    description:
        'Things get heated and you go blank. No words, maybe you want to leave the room, or you feel far away while they\'re still talking. It\'s less a choice, more the words disappearing.',
  ),
  OnboardingQuestion(
    'Can you name what you need without blaming the other person?',
    description:
        '"I need a heads-up when plans change" versus "you always do this to me." Same frustration, different sentence. When you\'re actually annoyed, which one comes out?',
  ),
  OnboardingQuestion(
    'Do you feel uneasy when a partner needs too much closeness?',
    description:
        'They want to text all day, talk through everything, spend most free time together. Does that feel good — or does something in you tighten up and want room?',
  ),
  OnboardingQuestion(
    'Do you replay conversations long after they happen?',
    description:
        'It\'s midnight and you\'re still rereading the chat, rewording what you said, wondering how it landed. Often about a conversation that seemed completely fine at the time.',
  ),
  OnboardingQuestion(
    'Do you trust that repair is possible after disagreement?',
    description:
        'You\'ve just had a bad fight. Do you assume you\'ll find your way back to each other — or does it feel like something might be permanently broken now?',
  ),
  OnboardingQuestion(
    'Do you often need proof that someone still cares?',
    description:
        'They said they love you last week. Does that carry you through today — or do you need a reply, a text, something today before you feel settled again?',
  ),
  OnboardingQuestion(
    'Do you avoid sharing needs that might inconvenience someone?',
    description:
        'You say "I don\'t mind" when you do mind. You skip mentioning the thing that hurt because the evening is going well. Do you edit yourself to keep things easy?',
  ),
  OnboardingQuestion(
    'Can you receive feedback without feeling attacked?',
    description:
        'They say "when you did that, it bothered me." Can you stay curious about how it felt for them — or does your mind jump straight to defending yourself?',
  ),
  OnboardingQuestion(
    'Do you become more distant when you feel misunderstood?',
    description:
        'You tried to explain and they still didn\'t get it. Do you try again another way — or do you go quiet, share less, and stop bothering?',
  ),
  OnboardingQuestion(
    'Do you know the difference between a request and a demand?',
    description:
        'You ask them to call you when they land. They forget. Do you just let it go — or do they get the cold shoulder, a lecture, or a guilt trip about it later?',
  ),
  OnboardingQuestion(
    'Do you feel grounded when a partner has their own life?',
    description:
        'They\'ve got a weekend away with friends, a hobby you don\'t share, someone else they confide in. Does that sit fine with you — honestly, inside, not just what you say out loud?',
  ),
  OnboardingQuestion(
    'Do you find silence from someone close hard to tolerate?',
    description:
        'Message left on read. A quiet evening after a tense moment. A day with no contact when there usually is. Is that just quiet — or is it loud and hard to sit through?',
  ),
  OnboardingQuestion(
    'Can you apologize without losing your sense of self?',
    description:
        'You owe an apology and you know it. Does saying "I was wrong" feel like fixing something — or like giving something up, like you lose a bit of yourself?',
  ),
  OnboardingQuestion(
    'Do you sometimes test whether someone really cares?',
    description:
        'Instead of asking, you pull back a little to see if they come after you. Or stay quiet about something that hurt, to see if they notice. Most people only spot this afterwards.',
  ),
  OnboardingQuestion(
    'Do you need emotional independence to feel safe?',
    description:
        'You\'re getting closer to someone, and it\'s going well. Do you still want a part of yourself that stays just yours — your own thoughts, your own decisions — or does the closeness itself feel like what makes you feel safe?',
  ),
  OnboardingQuestion(
    'Can you describe your relationship patterns clearly?',
    description:
        'Think back over your past relationships or close friendships. Do you notice yourself doing the same thing each time — the same kind of argument, the same moment things start going wrong? Or does each one just feel like its own separate story?',
  ),
  OnboardingQuestion(
    'Do you believe closeness can be steady without being perfect?',
    description:
        'Bad weeks, things you\'ll never fully agree on, stretches where you feel distant. Can a good relationship include all that — or does it mean something is wrong?',
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
