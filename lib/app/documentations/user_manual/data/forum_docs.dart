// lib/app/documentations/user_manual/data/forum_docs.dart
//
// Documents Forums. Sourced from lib/architecture/FORUM.md
// (Section 5 — the Forums feature and debate rooms).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ForumDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Forums';

  @override
  String get id => 'forums';

  @override
  String getSubtitle(BuildContext context) =>
      'Live, anonymous debates — pick a side, make your case';

  @override
  IconData get icon => Icons.groups_outlined;

  @override
  int get order => 20;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'forum_what_it_is',
      title: 'What Forums are',
      subtitle: 'Real debates, voted into existence',
      icon: Icons.gavel_outlined,
      category: 'Forums',
      order: 1,
      contents: [
        ManualContent(
          id: 'forum_intro',
          title: 'Topics the community votes on',
          numberPrefix: '1',
          content:
              'Forums are live debate rooms where people argue FOR or AGAINST a topic — like "Long distance relationships never really work." Anyone can submit a topic idea, and it only becomes a live forum once enough people vote it in.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'forum_anonymous',
          title: '',
          content:
              'Like Opinions, Forums are fully anonymous — only your relationship status is shown alongside your posts, never your name or photo.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'forum_submitting',
      title: 'Submitting and voting on topics',
      subtitle: 'A topic needs real support to go live',
      icon: Icons.how_to_vote_outlined,
      category: 'Forums',
      order: 2,
      contents: [
        ManualContent(
          id: 'forum_submit',
          title: 'Submitting a topic',
          content:
              'Anyone can submit a debatable topic (up to 120 characters). Once submitted, other users can upvote it (meaning "I\'m FOR this") or downvote it ("I\'m AGAINST this") — this also decides which side you\'ll be on if it goes live.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'forum_activation',
          title: 'When a topic goes live',
          content:
              'A topic needs more than half of the people who\'ve seen it to vote it up, with a real minimum number of votes, before it activates as a live forum. If it doesn\'t reach that within 14 days, it quietly expires — no notification either way for people who saw it but didn\'t vote.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'forum_side_locked',
          title: '',
          content:
              'How you vote on a topic decides your side if it activates. If you didn\'t vote and the forum goes live, you\'ll be asked to pick FOR, AGAINST, or just browse without posting.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'forum_debate_room',
      title: 'Inside the debate room',
      subtitle: 'One conversation, both sides',
      icon: Icons.forum_outlined,
      category: 'Forums',
      order: 3,
      contents: [
        ManualContent(
          id: 'forum_single_feed',
          title: 'A single, real-time conversation',
          content:
              'Posts from both sides appear in one chronological feed, like a group chat — your own posts on the right, everyone else\'s on the left, with a small badge showing whether each post is FOR or AGAINST.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'forum_cross_side_reply',
          title: 'Replying across sides',
          content:
              'You can directly reply to a post from the opposite side — that\'s what makes it a real debate rather than two separate monologues talking past each other.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'forum_side_lock',
          title: '',
          content:
              'Once you\'ve picked a side, you can only post on that side for this forum — you can\'t argue both ways in the same debate.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'forum_browse_only',
          title: 'Just browsing',
          content:
              'You can always read a full debate without picking a side or posting — browsing never counts you as a contributor.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'forum_insight',
      title: 'The Forum Insight',
      subtitle: 'A neutral look at how the debate is going',
      icon: Icons.insights_outlined,
      category: 'Forums',
      order: 4,
      contents: [
        ManualContent(
          id: 'forum_insight_what',
          title: '',
          content:
              'Tapping the info icon in a debate room opens a neutral summary of how the conversation is unfolding — not a scoreboard declaring a winner, just a way to get a sense of the debate at a glance.',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_forum_topic_live',
        question: 'What makes a submitted topic become a live forum?',
        answer:
            'More than half the people who\'ve seen the topic need to vote it up, along with a minimum overall number of votes. If that threshold isn\'t reached within 14 days, the topic quietly expires.',
        category: 'Forums',
        order: 1,
      ),
      FAQModel(
        id: 'faq_forum_side_choice',
        question: 'How is my side (FOR or AGAINST) decided?',
        answer:
            'It comes from how you voted when the topic was up for votes. If you didn\'t vote and the forum later activates, you\'ll be asked to pick a side (or just browse) the first time you open it.',
        category: 'Forums',
        order: 2,
      ),
      FAQModel(
        id: 'faq_forum_switch_side',
        question: 'Can I switch sides in an active debate?',
        answer:
            'No — once you\'ve picked a side for a specific forum, you can only post on that side for that debate.',
        category: 'Forums',
        order: 3,
      ),
      FAQModel(
        id: 'faq_forum_reply_other_side',
        question: 'Can I reply to someone arguing the opposite side?',
        answer:
            'Yes — replying across sides is not only allowed, it\'s the point. That\'s what makes it a real back-and-forth debate rather than two separate threads.',
        category: 'Forums',
        order: 4,
      ),
      FAQModel(
        id: 'faq_forum_browse',
        question: 'Do I have to pick a side to read a forum?',
        answer:
            'No — you can always browse and read the full debate without picking a side. You just won\'t be able to post, and browsing never counts as contributing.',
        category: 'Forums',
        order: 5,
      ),
      FAQModel(
        id: 'faq_forum_anonymous',
        question: 'Is my identity visible to other people in a forum?',
        answer:
            'No — like Opinions, only your relationship status appears next to your posts. Your name, photo, and username are never shown.',
        category: 'Forums',
        order: 6,
      ),
    ];
  }
}
