// Every manual topic is well formed: unique ids, no empty sections, balanced
// **bold**, no clinician-pending [DRAFT] wording, and every related or gated
// id points at a registered topic.
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every topic is well formed', (tester) async {
    DocumentationRegistry.initialize();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final modules = DocumentationRegistry.getAllModules();
    expect(modules.length, greaterThanOrEqualTo(33));
    final ids = <String>{};
    final sectionIds = <String>{};
    final faqIds = <String>{};
    for (final m in modules) {
      expect(ids.add(m.id), isTrue, reason: 'duplicate module id ${m.id}');
      expect(m.getTitle(context).trim(), isNotEmpty, reason: m.id);
      final sections = m.getSections(context);
      expect(sections, isNotEmpty, reason: '${m.id} has no sections');
      final texts = <String>[m.getTitle(context), m.getSubtitle(context)];
      for (final s in sections) {
        expect(
          sectionIds.add(s.id),
          isTrue,
          reason: 'duplicate section id ${s.id}',
        );
        expect(s.contents, isNotEmpty, reason: '${m.id}/${s.id} is empty');
        texts.add(s.title);
        for (final c in s.contents) {
          texts.addAll([c.title, c.content, ...?c.bulletPoints]);
          if (c.type == ManualContentType.bulletList) {
            expect(
              c.bulletPoints ?? const [],
              isNotEmpty,
              reason: '${s.id}/${c.id}',
            );
          } else if (c.type != ManualContentType.image &&
              c.type != ManualContentType.code) {
            expect(
              c.content.trim(),
              isNotEmpty,
              reason: '${s.id}/${c.id} has no text',
            );
          }
        }
      }
      for (final f in m.getFAQs(context)) {
        expect(
          faqIds.add('${m.id}/${f.id}'),
          isTrue,
          reason: 'duplicate FAQ ${f.id}',
        );
        texts.addAll([f.question, f.answer]);
      }
      for (final t in texts) {
        expect(
          '**'.allMatches(t).length.isEven,
          isTrue,
          reason: '${m.id}: unbalanced ** in "$t"',
        );
        expect(
          t.contains('[DRAFT]'),
          isFalse,
          reason: '${m.id}: draft wording in "$t"',
        );
      }
    }
    for (final m in modules) {
      for (final r in DocumentationRegistry.getRelatedModuleIds(m.id)) {
        expect(ids, contains(r), reason: '${m.id} relates to unknown $r');
      }
      // A link opens a topic in place, like the Related tab, so it may only
      // point at one of this topic's related ids.
      for (final s in m.getSections(context)) {
        for (final c in s.contents.where(
          (c) => c.type == ManualContentType.link,
        )) {
          expect(
            DocumentationRegistry.getRelatedModuleIds(m.id),
            contains(c.linkedModuleId),
            reason: '${m.id}/${c.id} links outside its related topics',
          );
        }
      }
    }
    for (final gated in const [
      'hardMoment',
      'safetyCheck',
      'appreciation',
      'shareAWin',
      'quietStates',
      'coupleMap',
      'communicationQuiz',
      'conflictStyleQuiz',
    ]) {
      expect(ids, contains(gated));
      expect(
        DocumentationRegistry.requiredFlags(gated),
        isNotEmpty,
        reason: gated,
      );
    }
  });
}
