// lib/app/documentations/user_manual/data/chat_docs.dart
//
// Documents Chat — Attune's private messaging space for a couple. Content is
// sourced from lib/architecture/CHAT_SYSTEM_SPEC.md and limited to what a
// user actually sees; the spec's internal safety/analysis machinery is
// intentionally omitted per that spec's own rule that Chat must never expose
// hidden AI judgments to the people using it.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ChatDocs implements DocumentationModule {
  @override
  int get order => 3;

  @override
  String getTitle(BuildContext context) => 'Chat';

  @override
  String get id => 'chat';

  @override
  String getSubtitle(BuildContext context) =>
      'Your private space to talk with your partner';

  @override
  IconData get icon => Icons.chat_bubble_outline;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'chat_what_it_is',
      title: 'What Chat is',
      subtitle: 'A private conversation, just the two of you',
      icon: Icons.chat_bubble_outline,
      category: 'Chat',
      order: 1,
      contents: [
        ManualContent(
          id: 'chat_purpose',
          title: 'Built for the two of you',
          numberPrefix: '1',
          content:
              'Chat is where you and your partner talk, day to day. It works like messaging apps you already know — send a message, see when it\'s delivered, see when it\'s read.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_not_public',
          title: 'It\'s not a public or group space',
          numberPrefix: '2',
          content:
              'Chat is only ever between you and your one active partner. There\'s no group chat, no strangers, no public feed here — that lives in other parts of the app, like Opinions and Forums.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_encryption_note',
          title: '',
          content:
              'Chat is not end-to-end encrypted the way some messaging apps are. Attune\'s servers can access message content because that access is what lets features like the Verdict system, Pulse, and pattern insights work — always with your explicit awareness, never hidden. You can read exactly what Attune does and doesn\'t do with your messages in Settings → Privacy.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'chat_sending',
      title: 'Sending messages',
      subtitle: 'What the ticks and statuses mean',
      icon: Icons.send_outlined,
      category: 'Chat',
      order: 2,
      contents: [
        ManualContent(
          id: 'chat_statuses',
          title: 'Message statuses',
          content: 'Every message you send moves through a few stages:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Sending:** Your message is on its way — this can happen instantly, or take a moment if you\'re on a weak connection.',
            '**Sent:** It\'s reached Attune\'s servers.',
            '**Delivered:** It\'s reached your partner\'s device.',
            '**Read:** Your partner has opened the conversation and seen it.',
          ],
        ),
        ManualContent(
          id: 'chat_offline',
          title: 'What happens if you lose connection',
          content:
              'If you send a message with no internet connection, it waits in a queue on your device and sends automatically the moment you\'re back online — you don\'t need to do anything or resend it yourself.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_failed',
          title: '',
          content:
              'If a message truly can\'t be sent — for example, your account lost access to the conversation — you\'ll see a clear "failed" mark with the option to retry or remove it. A message only ever shows as failed when it genuinely needs your attention, never for an ordinary retry happening quietly in the background.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'chat_photos',
      title: 'Sharing photos',
      subtitle: 'Coming to Chat',
      icon: Icons.image_outlined,
      category: 'Chat',
      order: 3,
      contents: [
        ManualContent(
          id: 'chat_photos_intro',
          title: 'Private photo sharing',
          content:
              'Chat will support sending a photo alongside your message. Photos are stored privately — only you and your partner can view them, using a temporary secure link generated each time, never a public URL. Location and other identifying details are automatically stripped from any photo before it\'s stored.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'chat_translator',
      title: '"Help me say this"',
      subtitle: 'Get help wording a hard message',
      icon: Icons.auto_fix_high,
      category: 'Chat',
      order: 4,
      contents: [
        ManualContent(
          id: 'chat_translator_what',
          title: 'What it does',
          content:
              'While writing a message, you can tap "Help me say this" to get a suggested rewrite that says what you mean without escalating a hard conversation. This is entirely optional and only appears when you have text already typed.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_translator_control',
          title: 'You\'re always in control',
          content: 'Nothing is sent automatically. You choose to:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Send your original message as written',
            'Send the suggested rewrite instead',
            'Edit the rewrite before sending',
          ],
        ),
        ManualContent(
          id: 'chat_translator_invisible',
          title: '',
          content:
              'Your partner only ever sees the final message you chose to send — there\'s no label or indicator showing a rewrite was used. What you draft before sending is private to you, even from your partner.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'chat_import',
      title: 'Bringing in past conversations',
      subtitle: 'An optional, both-partners-required feature',
      icon: Icons.history,
      category: 'Chat',
      order: 5,
      contents: [
        ManualContent(
          id: 'chat_import_what',
          title: 'What it is',
          content:
              'If your relationship existed before Attune, you can choose to import a previous conversation history (starting with WhatsApp exports) so the app has more to work with sooner — rather than starting from nothing.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_import_consent',
          title: 'Both of you must agree — no exceptions',
          content:
              'This is never a one-person decision. If you request an import, your partner sees a plain-language explanation of exactly what will happen and must independently approve it before anything is imported. Your partner is never shown the message content while deciding — only what the import would involve. If they decline, you\'re only told they chose not to proceed; their reasoning, if any, is never shared with you.',
          numberPrefix: '2',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'chat_import_analyzed',
          title: 'Imported messages are treated like real messages',
          content:
              'Once both of you agree, imported messages become part of your Attune chat history, dated as they actually happened, and are read by the same systems that read new messages — including safety checks. This is disclosed clearly before either of you agrees, so there are no surprises later.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'chat_import_delete',
          title: '',
          content:
              'Either partner can delete imported history at any time, independently — you don\'t need your partner\'s permission to remove it, only to add it in the first place.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'chat_relationship_states',
      title: 'When a relationship changes',
      subtitle: 'What happens to your chat history',
      icon: Icons.info_outline,
      category: 'Chat',
      order: 6,
      contents: [
        ManualContent(
          id: 'chat_states_list',
          title: 'Chat follows your relationship status',
          content: '',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Active:** Full chat — send and read freely.',
            '**Paused or ended:** You can still read your history, but you can no longer send new messages.',
            '**Archived:** The chat becomes inaccessible, and anything cached on your device is cleared. This normally happens automatically if either of you later starts a new active relationship on Attune.',
          ],
        ),
        ManualContent(
          id: 'chat_reflections_separate',
          title: '',
          content:
              'Personal Reflections (your private journal) is completely separate from Chat — nothing you write there is ever inserted into a conversation or shown to your partner.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_chat_encrypted',
        question: 'Is my chat end-to-end encrypted?',
        answer:
            'No — not the way some messaging apps are. Your messages are encrypted in transit and at rest, but Attune\'s servers can process message content, because that\'s what powers features like Pulse, pattern insights, and the Verdict system. This is disclosed openly, never hidden, and you can read the full detail in Settings → Privacy.',
        category: 'Chat',
        order: 1,
      ),
      FAQModel(
        id: 'faq_chat_who_sees',
        question: 'Can anyone besides my partner read my messages?',
        answer:
            'No other user can. Only you and your current active partner can read your conversation. Attune\'s automated systems may process messages for the features described in Settings → Privacy, but message content is never shown to another person, never used to train AI models, and never appears in logs or analytics.',
        category: 'Chat',
        order: 2,
      ),
      FAQModel(
        id: 'faq_chat_group',
        question: 'Can I chat with more than one person?',
        answer:
            'Chat is one-to-one, just you and your current partner. There\'s no group chat inside Attune\'s Chat feature.',
        category: 'Chat',
        order: 3,
      ),
      FAQModel(
        id: 'faq_chat_lost_internet',
        question: 'What happens if I send a message with no internet?',
        answer:
            'It\'s saved on your device and sent automatically as soon as you\'re back online. You don\'t need to resend it yourself.',
        category: 'Chat',
        order: 4,
      ),
      FAQModel(
        id: 'faq_chat_translator_visible',
        question: 'Will my partner know I used "Help me say this"?',
        answer:
            'No. Your partner only ever sees the final message you choose to send — there\'s no indicator or label showing you used the rewrite tool.',
        category: 'Chat',
        order: 5,
      ),
      FAQModel(
        id: 'faq_chat_import_force',
        question: 'Can my partner import our old messages without my say-so?',
        answer:
            'No. Importing a previous conversation always requires both of you to independently agree, in full, after seeing the same plain-language explanation. Neither of you can approve it on the other\'s behalf, and there\'s no way to import with only one person\'s consent.',
        category: 'Chat',
        order: 6,
      ),
      FAQModel(
        id: 'faq_chat_ended_relationship',
        question:
            'Can I still read old messages after my relationship ends?',
        answer:
            'Yes — ending a relationship makes chat read-only, not deleted. You can still scroll back and read your history, you just can\'t send new messages. If you later start a new active relationship on Attune, the old chat becomes archived and fully inaccessible.',
        category: 'Chat',
        order: 7,
      ),
      FAQModel(
        id: 'faq_chat_reflections',
        question:
            'Is what I write in Personal Reflections shared in Chat?',
        answer:
            'Never. Personal Reflections is a completely separate, private space. Nothing you write there is ever inserted into a conversation or made visible to your partner.',
        category: 'Chat',
        order: 8,
      ),
    ];
  }
}
