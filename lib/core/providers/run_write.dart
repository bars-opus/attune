import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a write held in a `FutureProvider.family` exactly once per call.
///
/// Such a provider keeps its result for good, keyed by its arguments: a
/// retry after a failure would replay the old error, and saving an edit
/// identical to an earlier one would write nothing. Clearing the entry once
/// the write settles makes every call a real write. The container is taken
/// up front, so the clean-up still runs if the screen closes meanwhile.
Future<T> runWrite<T>(WidgetRef ref, FutureProvider<T> write) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  try {
    return await container.read(write.future);
  } finally {
    container.invalidate(write);
  }
}
