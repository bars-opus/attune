// lib/app/documentations/user_manual/data/privacy_data_docs.dart
//
// Seen receipts and ticks (Spec 1a), private Pulse (Spec 1a), signed-in
// devices (Spec 2), Download my data (Spec 3c), Hide a period (Spec 7) and
// account deletion. Always listed.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class PrivacyDataDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Your privacy and data';

  @override
  String get id => 'privacyData';

  @override
  String getSubtitle(BuildContext context) =>
      'What your partner can see, what stays yours, and how to take it with you';

  @override
  IconData get icon => Icons.privacy_tip_outlined;

  @override
  int get order => 2;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'privacy_seen',
      title: 'Read ticks and "seen"',
      subtitle: 'Only when you both agree',
      icon: Icons.done_all,
      category: 'Privacy',
      order: 1,
      contents: [
        ManualContent(
          id: 'privacy_seen_setting',
          title: 'One setting, both of you',
          numberPrefix: '1',
          content:
              '"Show when we\'ve seen things", in the Pulse tab of your chat, controls read ticks and story "seen" marks. They show only when you have both turned it on. Either of you can turn it off at any time, and the other isn\'t told.',
        ),
        ManualContent(
          id: 'privacy_seen_ticks',
          title: 'What the ticks mean',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**One tick:** sent.',
            '**Two grey ticks:** delivered to their phone.',
            '**Two coloured ticks:** read — only while the setting is on for both of you.',
          ],
        ),
        ManualContent(
          id: 'privacy_seen_never_later',
          title: '',
          content:
              'Anything read while the setting is off is never revealed later, even if you both turn it on again.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'privacy_yours',
      title: 'What stays yours',
      subtitle: 'Private by default',
      icon: Icons.lock_outline,
      category: 'Privacy',
      order: 2,
      contents: [
        ManualContent(
          id: 'privacy_yours_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Your weekly check-in answers and your emotional-safety score ("Your week" in Pulse) — only you see them.',
            'Your journal, your appreciation jar and anything you mark quiet.',
            'Your love-language and quiz answers, unless you choose to share a result.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'privacy_hide_period',
      title: 'Hide a period',
      subtitle: 'Dates that never come back as memories',
      icon: Icons.visibility_off_outlined,
      category: 'Privacy',
      order: 3,
      contents: [
        ManualContent(
          id: 'privacy_hide_period_how',
          title: 'For dates you\'d rather not revisit',
          numberPrefix: '1',
          content:
              'Go to Settings → Hide a period and choose the dates. Nothing from them comes back in "On this day" or memory prompts for you. Nothing is deleted, and your partner isn\'t told.',
        ),
      ],
    ),
    ManualSection(
      id: 'privacy_devices',
      title: 'Where you\'re signed in',
      subtitle: 'See and sign out other phones',
      icon: Icons.devices_outlined,
      category: 'Privacy',
      order: 4,
      contents: [
        ManualContent(
          id: 'privacy_devices_how',
          title: 'Your phones, at a glance',
          numberPrefix: '1',
          content:
              'Settings → "Where you\'re signed in" lists each phone on your account, when it signed in and when it was last active. "Sign out all other devices" signs out every phone except this one; another phone can take up to an hour to notice.',
        ),
        ManualContent(
          id: 'privacy_devices_notice',
          title: '',
          content:
              'If a new device signs in to your account, Attune shows a notice the next time you open it, with a link to review your devices.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'privacy_export',
      title: 'Download my data',
      subtitle: 'A copy of what\'s yours',
      icon: Icons.download_outlined,
      category: 'Your data',
      order: 5,
      contents: [
        ManualContent(
          id: 'privacy_export_how',
          title: 'Ask, then download',
          numberPrefix: '1',
          content:
              'Go to Settings → Download my data and tap "Prepare my download". You can leave the screen while it\'s prepared. When it\'s ready, download it as one or more ZIP files within 7 days.',
        ),
        ManualContent(
          id: 'privacy_export_includes',
          title: 'What\'s included',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Your messages and the photos you shared, plans, calendar, reminders and moments.',
            'Your own stories, check-ins, journal and quiz answers.',
            'The insights and monthly readouts Attune showed you, and your settings.',
          ],
        ),
        ManualContent(
          id: 'privacy_export_never',
          title: '',
          content:
              'It never includes anything about safety, the behind-the-scenes analysis of your chats, or your partner\'s private data.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'privacy_export_limits',
          title: 'How often',
          numberPrefix: '3',
          content:
              'One download is prepared at a time, and you can ask for a new one 24 hours after the last one was ready. If you set a Safety PIN, Attune asks for it before preparing or downloading.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_privacy_seen_default',
      question: 'Why don\'t I see read ticks?',
      answer:
          'Read ticks show only when you have both turned on "Show when we\'ve seen things". For new couples it starts off. Turn it on together whenever you like.',
      category: 'Privacy',
      order: 1,
    ),
    FAQModel(
      id: 'faq_privacy_export_ended',
      question: 'Can I download our chat after we\'ve ended?',
      answer:
          'Yes, for the 30 days the chat stays readable, unless you sealed your side. After that it no longer appears in a download.',
      category: 'Your data',
      order: 2,
    ),
    FAQModel(
      id: 'faq_privacy_delete_account',
      question: 'What happens if I delete my account?',
      answer:
          'Your account and your personal data are deleted. A shared space you were in is ended without a notification, and your partner keeps their 30 days to read it.',
      category: 'Your data',
      order: 3,
    ),
  ];
}
