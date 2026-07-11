import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TypingState {
  const TypingState(this.partnerTyping);
  final bool partnerTyping;
}

/// Owns the ephemeral typing signal for one relationship: throttles outgoing
/// "typing" broadcasts while composing, and auto-expires the incoming
/// partner-typing indicator so it never sticks.
class TypingController extends StateNotifier<TypingState> {
  TypingController(this.ref, this.relationshipId)
    : super(const TypingState(false)) {
    _repository = ref.read(chatRepositoryProvider);
    _myId = ref.read(currentUserProvider)?.id;
    _sub = _repository.watchTyping(relationshipId).listen(_onPartnerEvent);
  }

  final Ref ref;
  final String relationshipId;
  late final ChatRepository _repository;
  String? _myId;
  StreamSubscription<TypingEvent>? _sub;

  Timer? _throttleTimer; // gates outgoing typing:true
  Timer? _expiryTimer; // clears incoming partnerTyping
  bool _composing = false;
  DateTime? _lastKeystroke; // last time onComposingChanged(true) was called

  static const _throttleInterval = Duration(seconds: 2);
  static const _expiryDuration = Duration(seconds: 5);
  // If no keystroke arrives within this window while text remains in the
  // composer (e.g. the user walked away), stop re-broadcasting typing:true
  // and clear the indicator on the partner's side — mirrors WhatsApp's
  // decay-on-inactivity behavior instead of decaying only on empty-text.
  static const _inactivity = Duration(seconds: 5);

  void onComposingChanged(bool hasText) {
    if (hasText) {
      _lastKeystroke = DateTime.now();
      if (!_composing) {
        _composing = true;
        _sendTyping(true);
        _startThrottle();
      }
      // while composing, the throttle timer re-sends periodically
    } else {
      if (_composing) {
        _composing = false;
        _throttleTimer?.cancel();
        _throttleTimer = null;
        _sendTyping(false);
      }
    }
  }

  void onSent() {
    _composing = false;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _sendTyping(false);
  }

  void _startThrottle() {
    _throttleTimer?.cancel();
    _throttleTimer = Timer.periodic(_throttleInterval, (_) {
      if (!_composing) {
        _throttleTimer?.cancel();
        _throttleTimer = null;
        return;
      }
      final lastKeystroke = _lastKeystroke;
      if (lastKeystroke != null &&
          DateTime.now().difference(lastKeystroke) >= _inactivity) {
        // No keystrokes for a while despite text remaining in the composer —
        // stop re-sending and clear the partner's indicator promptly.
        _throttleTimer?.cancel();
        _throttleTimer = null;
        _composing = false;
        _sendTyping(false);
        return;
      }
      _sendTyping(true);
    });
  }

  void _sendTyping(bool typing) {
    _repository.sendTyping(relationshipId, typing: typing);
  }

  void _onPartnerEvent(TypingEvent event) {
    if (event.senderId == _myId) return; // ignore own echo
    if (event.typing) {
      if (mounted) state = const TypingState(true);
      _expiryTimer?.cancel();
      _expiryTimer = Timer(_expiryDuration, () {
        if (mounted) state = const TypingState(false);
      });
    } else {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      if (mounted) state = const TypingState(false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _throttleTimer?.cancel();
    _expiryTimer?.cancel();
    // Best-effort: tell the partner we stopped when the view goes away.
    if (_composing) _repository.sendTyping(relationshipId, typing: false);
    super.dispose();
  }
}

final typingControllerProvider = StateNotifierProvider.autoDispose
    .family<TypingController, TypingState, String>(
        (ref, relationshipId) => TypingController(ref, relationshipId));
