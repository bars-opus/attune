import 'story_outbox_backend_base.dart';
import 'story_outbox_backend_stub.dart'
    if (dart.library.io) 'story_outbox_backend_io.dart'
    if (dart.library.html) 'story_outbox_backend_web.dart';

export 'story_outbox_backend_base.dart' show StoryOutboxBackend;

StoryOutboxBackend createDefaultStoryOutboxBackend() =>
    createStoryOutboxBackend();
