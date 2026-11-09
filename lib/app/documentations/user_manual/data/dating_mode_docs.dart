// lib/app/documentations/user_manual/data/dating_mode_docs.dart
//
// Dating (Spec 2, docs/superpowers/specs/2026-10-24-dating-mode-design.md).
// Listed only while flow_signin_v2, flow_paths_v2 and dating_mode_enabled
// are on (DocumentationRegistry). Healing never decides when someone can
// date (§2.1); nothing here says otherwise.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class DatingModeDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Dating';

  @override
  String get id => 'datingMode';

  @override
  String getSubtitle(BuildContext context) =>
      'Up to 3 introductions a day, never a swipe deck';

  @override
  IconData get icon => Icons.favorite_border;

  @override
  int get order => 21;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'dating_what_it_is',
      title: 'What Dating is',
      subtitle: 'A few introductions, chosen with care',
      icon: Icons.favorite_border,
      category: 'Dating',
      order: 1,
      contents: [
        ManualContent(
          id: 'dating_intro',
          title: 'Up to 3 introductions a day',
          numberPrefix: '1',
          content:
              'Dating introduces you to up to 3 people a day, at a time you choose. Each introduction says why you two were introduced: what you could do together and what you both say you value. There is no swipe deck, no browsing, no counters and no streaks.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_not_prediction',
          title: '',
          content:
              'Attune can\'t predict chemistry; meeting is how you find out.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'dating_who',
          title: 'Who can use it',
          numberPrefix: '2',
          content:
              'Dating is for adults whose account is in good standing, who aren\'t married or in a relationship, in a country where Attune has opened Dating. Healing never decides when you can date. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_inputs',
          title: '',
          content:
              'Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_setup',
      title: 'Setting up',
      subtitle: 'One question per screen',
      icon: Icons.checklist_outlined,
      category: 'Dating',
      order: 2,
      contents: [
        ManualContent(
          id: 'dating_setup_steps',
          title: 'Twelve short steps',
          numberPrefix: '1',
          content:
              'You choose what you\'re looking for, where you are, how you describe yourself, who you\'d like to meet, children and, if you like, faith. Then you add 2 to 6 photos and answer 2 short prompts. You can stop at any step and carry on later.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_private',
          title: 'What stays private',
          numberPrefix: '2',
          content:
              'Nobody ever sees who you\'d like to meet, your exact location or your date of birth. Your gender, faith and marriage history appear on your profile only if you choose.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_photos',
          title: 'Your photos',
          numberPrefix: '3',
          content:
              'Every photo is checked before anyone sees it. Photos with children can\'t be used. From your account\'s 30th day you can choose to show your photos only after you\'re both interested.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_verify',
          title: 'Checking it\'s you',
          numberPrefix: '4',
          content:
              'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_interest',
      title: 'Interest and matches',
      subtitle: 'Both of you, or nothing',
      icon: Icons.thumb_up_alt_outlined,
      category: 'Dating',
      order: 3,
      contents: [
        ManualContent(
          id: 'dating_double_opt_in',
          title: 'A match needs both of you',
          numberPrefix: '1',
          content:
              'You answer each introduction with "Interested" or "Not for me". Nobody is told you passed. A match appears only when you\'re both interested.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_former_partner',
          title: 'Former partners are never introduced',
          numberPrefix: '2',
          content:
              'A former Attune partner is never introduced to you, even if either of you later makes a new account.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_money',
          title: '',
          content:
              'Never send money, account details or mobile money to someone you haven\'t met in person, whatever the story. Report it from the conversation.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_privacy_on_phone',
      title: 'On your phone',
      subtitle: 'Discreet by design',
      icon: Icons.lock_outline,
      category: 'Dating',
      order: 4,
      contents: [
        ManualContent(
          id: 'dating_notifications',
          title: 'Plain notifications',
          numberPrefix: '1',
          content:
              'Dating notifications never mention Dating. They show only "Attune" and a short line: "You have something new in Attune." or, for something you asked to be told about, "Something you asked about is ready in Attune." Tapping one opens Me.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_lock',
          title: 'The Dating lock',
          numberPrefix: '2',
          content:
              'If someone else uses your phone, you can lock Dating with your Safety PIN in Dating settings, and ask for the PIN every time Attune opens.',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_control',
      title: 'Pausing and leaving',
      subtitle: 'Whenever you want',
      icon: Icons.pause_circle_outline,
      category: 'Dating',
      order: 5,
      contents: [
        ManualContent(
          id: 'dating_pause',
          title: 'Pause Dating',
          numberPrefix: '1',
          content:
              'Pausing means nobody new sees you, and your conversations stay open. Nobody is told.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_leave',
          title: 'Leave Dating and delete my data',
          numberPrefix: '2',
          content:
              'Leaving deletes your Dating profile, photos, prompts, who you\'d like to meet, your gender and faith answers, your settings and your private notes straight away. Your conversations are kept for 30 days so either of you can still report a problem, then deleted. Only if your account is restricted or you\'ve blocked someone, a code made from your phone number, never the number itself, is kept for safety for up to 2 years. A record of when you agreed to Dating\'s terms and when you left is kept. Your "Never introduce me" list is kept only if you tick the box to keep it in case you come back; it holds codes, not numbers.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_not_auto_relationship',
          title: '',
          content:
              'A match never creates an Attune relationship on its own. Becoming a couple on Attune is a separate step you both choose.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_dating_when_available',
        question: 'When can I use Dating?',
        answer:
            'When you choose, as an adult whose account is in good standing, who isn\'t married or in a relationship, in a country where Dating is open. Healing never decides it. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it; you can set up Dating in the meantime.',
        category: 'Dating',
        order: 1,
      ),
      FAQModel(
        id: 'faq_dating_swipe',
        question: 'Is Dating a swiping app?',
        answer:
            'No. There is no swipe deck, no browsing and no counters. You get up to 3 introductions a day, each with the reasons you two were introduced.',
        category: 'Dating',
        order: 2,
      ),
      FAQModel(
        id: 'faq_dating_not_open',
        question: 'Why isn\'t Dating open where I live?',
        answer:
            'Attune opens Dating one country at a time, so it can keep it safe and well looked after. You can ask to be told when it opens where you are.',
        category: 'Dating',
        order: 3,
      ),
      FAQModel(
        id: 'faq_dating_rejection_visible',
        question: 'Will someone know if I said "Not for me"?',
        answer:
            'No. Nobody is told you passed. A match appears only when you\'re both interested.',
        category: 'Dating',
        order: 4,
      ),
      FAQModel(
        id: 'faq_dating_who_sees',
        question: 'Who sees my answers?',
        answer:
            'Nobody sees who you\'d like to meet, your exact location or your date of birth. Your gender, faith and marriage history show on your profile only if you turn them on.',
        category: 'Dating',
        order: 5,
      ),
      FAQModel(
        id: 'faq_dating_money_request',
        question: 'A match is asking me for money. Is that normal?',
        answer:
            'No. Never send money, account details or mobile money to someone you haven\'t met in person, whatever the reason. Report it from the conversation.',
        category: 'Dating',
        order: 6,
      ),
      FAQModel(
        id: 'faq_dating_leave',
        question: 'What happens to my data if I leave?',
        answer:
            'Your Dating profile, photos and answers are deleted straight away. Conversations are kept for 30 days so either of you can report a problem, then deleted. Only if your account is restricted or you\'ve blocked someone, a code made from your phone number, never the number itself, is kept for safety for up to 2 years. A record of when you agreed to Dating\'s terms and when you left is kept. Your "Never introduce me" list is kept only if you choose to keep it when you leave.',
        category: 'Dating',
        order: 7,
      ),
    ];
  }
}
