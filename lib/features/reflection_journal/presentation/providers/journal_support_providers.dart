import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The entries the crisis check answered `support_offered` for, this run
/// and this account only: never stored on the phone, never sent anywhere
/// (Spec 1 §6.6). Emptied when the signed-in account changes and on sign-out
/// and quick exit (D8, batch-8 review I-1).
class JournalSupportOffers extends Notifier<Set<String>> {
  final _tickets = <String, int>{};

  /// The account this state belongs to.
  String? account;

  @override
  Set<String> build() {
    account = ref.watch(journalAccountProvider);
    _tickets.clear();
    JournalSupportMemory.track(this, ref, () => state = const {});
    return const {};
  }

  void offer(String entryId) => state = {...state, entryId};

  void dismiss(String entryId) => state = {...state}..remove(entryId);

  void dismissAll() => state = const {};

  /// A ticket for one analysis request of [entryId] (batch-8 review M-3):
  /// only the latest request's answer may put the card away or show a
  /// reflection again.
  int nextTicket(String entryId) =>
      _tickets[entryId] = (_tickets[entryId] ?? 0) + 1;

  bool isLatest(String entryId, int ticket) => _tickets[entryId] == ticket;
}

final journalSupportOffersProvider =
    NotifierProvider<JournalSupportOffers, Set<String>>(
      JournalSupportOffers.new,
    );

/// Ruling PF-C6: "Not now" on Patterns, this run and this account only
/// (never stored). A new support_offered answer brings the card back.
class JournalPatternsSupportDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(journalAccountProvider);
    JournalSupportMemory.track(this, ref, () => state = false);
    return false;
  }

  void dismiss() => state = true;

  void rearm() => state = false;
}

final journalPatternsSupportDismissedProvider =
    NotifierProvider<JournalPatternsSupportDismissed, bool>(
      JournalPatternsSupportDismissed.new,
    );

/// What one analysis answer means for this run (rulings PF-C7 and B7 R-1).
typedef JournalAnalysisListener =
    void Function(String entryId, int ticket, JournalAnalysis answer);

/// support_offered: the card for that entry, its reflection hidden
/// everywhere, Patterns read again (its summary gives way to the card) and
/// its card back. Anything else: the card put away; only a fresh reflection
/// (completed, written for the text as it is now) is shown again, and
/// Patterns is read again. An answer for an older request than the latest
/// for that entry changes nothing, except support_offered, which always
/// applies (fail safe; batch-8 M-3). An answer that lands after the account
/// changed is dropped (D8). Takes the notifiers now: the entry screen calls
/// this in initState, and the answer arrives after its dispose, when its ref
/// is gone.
JournalAnalysisListener journalAnalysisListener(WidgetRef ref) {
  final offers = ref.read(journalSupportOffersProvider.notifier);
  final hidden = ref.read(journalHiddenReflectionsProvider.notifier);
  final patterns = ref.read(journalPatternsSupportDismissedProvider.notifier);
  final epoch = ref.read(journalPatternsEpochProvider.notifier);
  final account = ref.read(journalAccountProvider);
  return (entryId, ticket, answer) {
    if (offers.account != account) return;
    if (answer.isSupportOffered) {
      hidden.hide(entryId);
      offers.offer(entryId);
      patterns.rearm();
      epoch.bump();
      return;
    }
    if (!offers.isLatest(entryId, ticket)) return;
    offers.dismiss(entryId);
    if (answer.isComplete) {
      hidden.reveal(entryId);
      epoch.bump();
    }
  };
}
