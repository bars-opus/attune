// Spec 7 (B2; plan review M14): a win reads as a win on the timeline; old
// rows without the column are ordinary moments.
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({bool? win}) => {
  'id': 'e1', 'relationship_id': 'r1', 'logged_by': 'u1', 'event_type': 'highlight',
  'title': 'Got the grant!', 'occurred_at': '2026-10-18', 'created_at': '2026-10-18T09:00:00Z',
  if (win != null) 'is_win': win,
};

void main() {
  test('is_win is read, defaulting to false', () {
    expect(TimelineEventModel.fromJson(_row(win: true)).isWin, isTrue);
    expect(TimelineEventModel.fromJson(_row()).isWin, isFalse);
    expect(TimelineEventModel.fromJson(_row(win: true)).eventTypeDisplay, 'Win');
    expect(TimelineEventModel.fromJson(_row()).eventTypeDisplay, 'Highlight');
    expect(TimelineEventModel.fromJson(_row(win: true)).toJson()['is_win'], isTrue);
  });
}
