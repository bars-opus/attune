// lib/app/documentations/user_manual/data/safety_docs.dart
//
// Documents the Safety System — Support Resources and Quick Exit. Sourced
// from lib/architecture/SAFETY_SYSTEM_SPEC.md. This is the most safety-
// critical doc in the registry: every claim here is checked against the
// spec's own "permanent invariants" (§1.2) so nothing here overstates what
// the system actually does.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class SafetyDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Safety & Support Resources';

  @override
  String get id => 'safety';

  @override
  String getSubtitle(BuildContext context) =>
      'Quiet, private support — always available, never advertised loudly';

  @override
  IconData get icon => Icons.shield_outlined;

  @override
  int get order => 2;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'safety_what_it_is',
      title: 'What this is',
      subtitle: 'Quiet routing to real help, honestly limited',
      icon: Icons.shield_outlined,
      category: 'Safety',
      order: 1,
      contents: [
        ManualContent(
          id: 'safety_intro',
          title: 'Support resources, not monitoring',
          numberPrefix: '1',
          content:
              'Attune includes a quiet safety net: if certain concerning language appears in a message you receive, support resources may quietly become available to you — with no accusation made, and no action taken against your partner.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'safety_honest_limits',
          title: '',
          content:
              'This is a best-effort resource-routing feature, not human monitoring, a clinical assessment, or emergency dispatch. It cannot promise to catch everything, and it cannot contact help on your behalf — you always stay in control of what happens next.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'safety_recipient_only',
          title: 'Only ever routed to you',
          content:
              'If this system ever surfaces resources, it\'s always to the person receiving a message, never the sender. Your partner is never told a match happened, never notified, and nothing about the delivery of that message looks any different to them.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'safety_no_punishment',
      title: 'What never happens',
      subtitle: 'No accusation, no penalty, ever',
      icon: Icons.block_flipped,
      category: 'Safety',
      order: 2,
      contents: [
        ManualContent(
          id: 'safety_no_action_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'No message is ever blocked, delayed, or modified.',
            'No account is locked, restricted, or reported automatically.',
            'The copy you see never says a partner is abusive or dangerous.',
            'Dismissing a resource screen never weakens future protection for you.',
            'Nothing here is ever used to train an AI model.',
          ],
        ),
        ManualContent(
          id: 'safety_free_access',
          title: '',
          content:
              'Support resources and Quick Exit are always free — never behind a paywall, never gated by relationship status.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'safety_resources_screen',
      title: 'The Support Resources screen',
      subtitle: 'Available any time, with or without a trigger',
      icon: Icons.support_outlined,
      category: 'Safety',
      order: 3,
      contents: [
        ManualContent(
          id: 'safety_manual_access',
          title: 'You can open it whenever you want',
          content:
              'This screen isn\'t only reachable when something triggers it — you can open it manually any time from Settings, no explanation needed and nothing logged as unusual.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'safety_calling_confirm',
          title: 'Confirmed before anything happens',
          content:
              'The app never auto-dials a number or opens a website on your behalf — you\'re always asked to confirm first. It will also gently remind you that calls or browsing history may be visible if you\'re on a shared or monitored device.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'safety_no_erase_claim',
          title: '',
          content:
              'Attune cannot promise to erase evidence of your internet or call activity on a device — please keep that in mind if a device you\'re using isn\'t fully private to you.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'safety_quick_exit',
      title: 'Quick Exit',
      subtitle: 'Leave the app instantly, from anywhere',
      icon: Icons.exit_to_app,
      category: 'Safety',
      order: 4,
      contents: [
        ManualContent(
          id: 'safety_quick_exit_how',
          title: 'How to trigger it',
          content:
              'From any screen in the app, triple-tap the Attune logo within about two seconds to instantly leave — the app is immediately replaced with a neutral, unbranded screen that works even offline.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'safety_quick_exit_button',
          title: '',
          content:
              'There\'s also a clearly labeled "Quick exit" button on the Support Resources screen itself, for anyone who prefers a visible button over the gesture.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'safety_pin',
          title: 'Returning to the app afterward',
          content:
              'Setting up Quick Exit requires you to create a separate safety PIN. That PIN — not just your fingerprint or face — is required to get back into the sensitive parts of the app after a quick exit, as an extra layer of protection.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'safety_app_switcher',
          title: 'App switcher privacy',
          content:
              'Separately from Quick Exit, Attune covers sensitive content with a neutral image whenever you switch away to another app, so a glance at your app switcher doesn\'t reveal what you were looking at.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_safety_partner_notified',
        question:
            'If resources appear for me, does my partner get told anything?',
        answer:
            'No, never. Your partner is never notified, and nothing about how their message was delivered changes in any way they could notice.',
        category: 'Safety',
        order: 1,
      ),
      FAQModel(
        id: 'faq_safety_action_taken',
        question:
            'Does anything happen to my partner\'s account if this triggers?',
        answer:
            'No. No message is blocked, no account is locked or reported, and no automatic action is taken against anyone. This feature only ever routes quiet support resources to you.',
        category: 'Safety',
        order: 2,
      ),
      FAQModel(
        id: 'faq_safety_guarantee',
        question: 'Can I rely on this to always catch a dangerous message?',
        answer:
            'No — please don\'t treat it that way. This is a best-effort feature with real limits, not comprehensive monitoring, a clinical assessment, or an emergency service. If you\'re in immediate danger, contact local emergency services directly.',
        category: 'Safety',
        order: 3,
      ),
      FAQModel(
        id: 'faq_safety_access_anytime',
        question:
            'Can I open the resources screen without something triggering it?',
        answer:
            'Yes — it\'s always available manually from Settings, any time, for any reason. You don\'t need a trigger to use it.',
        category: 'Safety',
        order: 4,
      ),
      FAQModel(
        id: 'faq_safety_dismiss_effect',
        question:
            'If I dismiss the resources screen, does that turn off future protection?',
        answer:
            'No. Dismissing only closes that particular screen — it never disables detection or weakens protection for you going forward.',
        category: 'Safety',
        order: 5,
      ),
      FAQModel(
        id: 'faq_safety_quick_exit_pin',
        question: 'Why do I need a separate PIN for Quick Exit?',
        answer:
            'The safety PIN is a deliberate extra layer, distinct from your regular biometric unlock, required specifically to return to sensitive content after a quick exit — this is intentional and cannot be bypassed with just a fingerprint or face scan.',
        category: 'Safety',
        order: 6,
      ),
      FAQModel(
        id: 'faq_safety_erase_history',
        question: 'Can Attune erase my browsing or call history?',
        answer:
            'No — Attune cannot make claims about erasing evidence of activity on your device. If you\'re concerned about a shared or monitored device, please keep that limitation in mind.',
        category: 'Safety',
        order: 7,
      ),
    ];
  }
}
