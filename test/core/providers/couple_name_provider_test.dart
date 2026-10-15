import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the couple's journal, in good English", () {
    expect(coupleJournalTitle('The Harolds'), "The Harolds' journal");
    expect(coupleJournalTitle('Desmond'), "Desmond's journal");
    expect(coupleJournalTitle(null), 'Couples journal');
  });
}
