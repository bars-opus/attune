import 'chat_cache_backend_base.dart';
import 'chat_cache_backend_stub.dart'
    if (dart.library.io) 'chat_cache_backend_io.dart'
    if (dart.library.html) 'chat_cache_backend_web.dart';

export 'chat_cache_backend_base.dart' show ChatCacheBackend;

ChatCacheBackend createChatCacheBackend() => createBackend();
