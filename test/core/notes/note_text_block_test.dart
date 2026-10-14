import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/planning_doc_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Saver extends NoteTextSaver {
  final saves = <List<Map<String, dynamic>>>[];
  final leaves = <List<Map<String, dynamic>>>[];
  final afters = <String?>[];
  NoteSaveResult next = const NoteSaved(version: 2, plainText: 'Hello');
  @override
  int get maxPlainChars => 10000;
  @override
  int get maxPayloadBytes => 16384;
  @override
  String get goneMessage => 'Gone.';
  @override
  String get conflictTitle => 'You changed this on another device';
  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) async {
    saves.add(ops);
    return next;
  }

  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) => leaves.add(ops);
  @override
  Future<void> afterSave(String? plainText) async => afters.add(plainText);
  @override
  void showError(BuildContext context, Object error) {}
}

Future<_Saver> _pump(WidgetTester t, {bool showSecond = true}) async {
  final saver = _Saver();
  final doc = PlanningDocController();
  addTearDown(doc.dispose);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: PlanningDocScope(
          controller: doc,
          child: showSecond
              ? NoteTextBlock(blockId: 'b1', delta: const [{'insert': '\n'}], version: 1, saverFor: (_) => saver)
              : const SizedBox(),
        ),
      ),
    ),
  ));
  return saver;
}

void main() {
  testWidgets('typing saves through the saver a second after the last key', (t) async {
    final saver = await _pump(t);
    t.state<NoteTextBlockState>(find.byType(NoteTextBlock)).controller.replaceText(
        0, 0, 'Hello', const TextSelection.collapsed(offset: 5));
    await t.pump(const Duration(milliseconds: 500));
    expect(saver.saves, isEmpty);
    await t.pump(NoteTextBlock.debounce);
    expect(saver.saves.single.first['insert'], startsWith('Hello'));
    expect(saver.afters, ['Hello']);
  });

  testWidgets('a conflict asks with the saver\'s own title', (t) async {
    final saver = await _pump(t);
    saver.next = const NoteConflict(ops: [{'insert': 'Theirs\n'}], version: 5, plainText: 'Theirs');
    t.state<NoteTextBlockState>(find.byType(NoteTextBlock)).controller.replaceText(
        0, 0, 'Mine', const TextSelection.collapsed(offset: 4));
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(find.text('You changed this on another device'), findsOneWidget);
  });
}
