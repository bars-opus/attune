// lib/app/documentations/user_manual/data/opinions_docs.dart
//
// Documents Opinions. Sourced from lib/architecture/FORUM.md
// (Sections 3 and 4 — the anonymity system and Opinions feature).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class OpinionsDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Opinions';

  @override
  String get id => 'opinions';

  @override
  String getSubtitle(BuildContext context) =>
      'Anonymous, honest thoughts from people navigating the same things';

  @override
  IconData get icon => Icons.forum_outlined;

  @override
  int get order => 19;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'opinions_what_it_is',
      title: 'What it is',
      subtitle: 'A public, text-only feed — fully anonymous',
      icon: Icons.chat_bubble_outline,
      category: 'Opinions',
      order: 1,
      contents: [
        ManualContent(
          id: 'opinions_intro',
          title: 'Say what you actually think, anonymously',
          numberPrefix: '1',
          content:
              'Opinions is a public, text-only feed where you can share honest thoughts about relationships, dating, and everything in between — completely anonymously. No name, no photo, no username appears anywhere.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_status_only',
          title: 'The only identity shown',
          content:
              'Every post shows just your relationship status (like "Single" or "Taken") and how long ago it was posted — nothing else that could identify you. If you change your status later, your older posts still show the status you had when you wrote them.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_internal_only',
          title: '',
          content:
              'Your account is still linked to your posts internally, purely for moderation and spam prevention — but this link is never exposed to other users, in any screen or any way.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'opinions_feed',
      title: 'The feed',
      subtitle: 'Following and Discover',
      icon: Icons.dynamic_feed_outlined,
      category: 'Opinions',
      order: 2,
      contents: [
        ManualContent(
          id: 'opinions_following_tab',
          title: 'Following',
          content:
              'Shows posts from the anonymous accounts you\'ve chosen to follow, newest first. It starts empty for new users — head to Discover to find voices you connect with.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_discover_tab',
          title: 'Discover',
          content:
              'Shows posts from everyone, with posts from people sharing your relationship status surfaced a bit higher — otherwise ordered by genuine engagement, not by any hidden AI targeting. There\'s no algorithm trying to keep you scrolling; it\'s simple, rule-based ordering.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'opinions_posting',
      title: 'Posting and interacting',
      subtitle: 'Text only, up to 5,000 characters',
      icon: Icons.edit_note,
      category: 'Opinions',
      order: 3,
      contents: [
        ManualContent(
          id: 'opinions_post_rules',
          title: 'Writing a post',
          content:
              'Posts are text-only — no images, video, or link previews — up to 5,000 characters. You\'ll always be asked to confirm before it goes live.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_edit_delete',
          title: 'Editing and deleting',
          content:
              'You can edit a post within 15 minutes of posting it; after that, it\'s permanently fixed. You can delete any of your own posts at any time, with no time limit.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_reactions',
          title: 'Likes, dislikes, and comments',
          content:
              'You can like or dislike a post (never both at once), and leave comments up to 5,000 characters. Comments can\'t be edited after posting, only deleted.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'opinions_no_own_like',
          title: '',
          content:
              'You can\'t like or dislike your own posts — that\'s intentional, not a bug.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'opinions_following_profiles',
      title: 'Following and profiles',
      subtitle: 'Anonymous-to-anonymous',
      icon: Icons.person_outline,
      category: 'Opinions',
      order: 4,
      contents: [
        ManualContent(
          id: 'opinions_follow',
          title: 'Following someone',
          content:
              'You can follow any anonymous account from their post — this simply follows their anonymous identity, never their real one. Tap anywhere on a post card to open their anonymous profile, showing just their status, follower count, and their posts — nothing that could reveal who they really are.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_opinions_who_sees_name',
        question: 'Can anyone see my name or photo on Opinions?',
        answer:
            'No, never. Opinions is fully anonymous — no name, photo, or username appears anywhere in the feed, comments, or profiles.',
        category: 'Opinions',
        order: 1,
      ),
      FAQModel(
        id: 'faq_opinions_identifiable',
        question:
            'Is there any way someone could figure out who I am from my posts?',
        answer:
            'Your posts show only your relationship status and post time — nothing else. Your account is linked internally only for moderation purposes and is never exposed to other users.',
        category: 'Opinions',
        order: 2,
      ),
      FAQModel(
        id: 'faq_opinions_edit_window',
        question: 'Can I edit a post after I\'ve shared it?',
        answer:
            'Yes, within 15 minutes of posting. After that window, the post is permanently fixed — though you can always delete it entirely, with no time limit.',
        category: 'Opinions',
        order: 3,
      ),
      FAQModel(
        id: 'faq_opinions_status_change',
        question:
            'If I change my relationship status, do my old posts update too?',
        answer:
            'No — each post keeps the status you had at the moment you posted it, so your history stays accurate to how things were at the time.',
        category: 'Opinions',
        order: 4,
      ),
      FAQModel(
        id: 'faq_opinions_algorithm',
        question: 'Is Discover using AI to target what I see?',
        answer:
            'No. Discover uses simple, rule-based ordering — favoring posts from people who share your relationship status and genuine engagement — never AI-driven targeting or hidden personalization.',
        category: 'Opinions',
        order: 5,
      ),
    ];
  }
}
