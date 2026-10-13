import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The text block the cursor is (or was last) in, as the plan's document
/// sees it: the ribbon formats it and Insert puts new blocks at its cursor.
class PlanningActiveText {
  const PlanningActiveText({
    required this.blockId,
    required this.controller,
    required this.version,
    required this.flush,
  });

  final String blockId;
  final QuillController controller;

  /// The server version this block's text was last saved or loaded at.
  final int Function() version;

  /// Saves any typing still waiting for its debounce. False when the save
  /// didn't go through (the block then keeps its text and stays as it is).
  final Future<bool> Function() flush;
}

/// Shared by the plan's document, its text blocks and its ribbon.
class PlanningDocController extends ChangeNotifier {
  PlanningActiveText? _active;
  String? _selectedBlockId;
  final Map<String, bool> _hasText = {};

  /// A text block that should take the cursor when it appears (a note just
  /// opened, a paragraph just inserted). Taken once.
  String? _pendingFocus;
  void focusWhenShown(String blockId) => _pendingFocus = blockId;
  bool takeFocus(String blockId) {
    if (_pendingFocus != blockId) return false;
    _pendingFocus = null;
    return true;
  }

  /// Kept after the text loses focus (tapping a ribbon button does that),
  /// so Home still formats it and Insert still knows where the cursor was.
  PlanningActiveText? get active => _active;

  /// The block last tapped that isn't text: Insert goes after it.
  String? get selectedBlockId => _selectedBlockId;

  /// True when any text block has something typed in it, saved or not.
  bool get anyText => _hasText.values.any((v) => v);

  void activate(PlanningActiveText text) {
    _active = text;
    _selectedBlockId = null;
    notifyListeners();
  }

  void select(String blockId) {
    if (_selectedBlockId == blockId && _active == null) return;
    _selectedBlockId = blockId;
    _active = null;
    notifyListeners();
  }

  /// A text block is going away (deleted, or the plan is closing). Called
  /// from its dispose, while Flutter is tearing the tree down — when no
  /// listener may be notified — so the ribbon hears about it after the
  /// frame, and not at all if this controller is gone by then.
  void forget(String blockId) {
    _hasText.remove(blockId);
    if (_active?.blockId == blockId) {
      _active = null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  /// The page's scroll, so a block added at the end can be scrolled to
  /// (a list does not build rows that are far off screen).
  final ScrollController scroll = ScrollController();

  /// Scrolls to the end of the page after the next frame, when the new
  /// block is in the list.
  void revealEnd() => SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !scroll.hasClients) return;
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      });

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    scroll.dispose();
    super.dispose();
  }

  void reportText(String blockId, bool hasText) => _hasText[blockId] = hasText;

  // ---- block motion -------------------------------------------------------

  final Set<String> _seen = {};
  bool _seeded = false;
  final Map<String, Completer<void>> _leaving = {};

  /// The blocks a plan opened with: they appear without animating.
  void seed(Iterable<String> blockIds) {
    if (_seeded) return;
    _seeded = true;
    _seen.addAll(blockIds);
  }

  /// True the first time a block is shown after the plan opened (inserted
  /// here, added by the partner, or brought back by Undo): it animates in.
  bool appeared(String blockId) => _seeded && _seen.add(blockId);

  bool isLeaving(String blockId) => _leaving.containsKey(blockId);

  /// Animates the block out; completes once it is gone from the page.
  Future<void> leave(String blockId) {
    final done = _leaving.putIfAbsent(blockId, Completer<void>.new);
    notifyListeners();
    return done.future;
  }

  /// Called by the block's motion when it has finished leaving. Quietly:
  /// the delete that follows rebuilds the page. Forgetting it lets an Undo
  /// animate it back in.
  void left(String blockId) {
    _seen.remove(blockId);
    _leaving.remove(blockId)?.complete();
  }

  /// A block removed without the collapse (a swipe already animated it).
  void unseen(String blockId) => _seen.remove(blockId);
}

class PlanningDocScope extends InheritedNotifier<PlanningDocController> {
  const PlanningDocScope({super.key, required PlanningDocController controller, required super.child})
      : super(notifier: controller);

  static PlanningDocController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanningDocScope>()?.notifier;

  /// Without subscribing to changes (for callbacks).
  static PlanningDocController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlanningDocScope>()?.notifier;
}
