import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../domain/shared_capture.dart';
import 'together_widget_sync.dart';

/// Where shares from other apps arrive (a seam for tests).
abstract class ShareSource {
  Future<List<SharedItem>> initial();
  Stream<List<SharedItem>> stream();
  Future<void> reset();
}

List<SharedItem> _items(List<SharedMediaFile> files) => [
  for (final f in files) SharedItem(f.type.value, f.path),
];

class ReceiveSharingIntentSource implements ShareSource {
  const ReceiveSharingIntentSource();

  @override
  Future<List<SharedItem>> initial() async =>
      _items(await ReceiveSharingIntent.instance.getInitialMedia());

  @override
  Stream<List<SharedItem>> stream() =>
      ReceiveSharingIntent.instance.getMediaStream().map(_items);

  /// The plugin forgets its in-memory copy; the extension's App Group copy
  /// is removed too, so a handled share leaves nothing on disk.
  @override
  Future<void> reset() async {
    await ReceiveSharingIntent.instance.reset();
    await TogetherWidgetSync.forgetShare();
  }
}
