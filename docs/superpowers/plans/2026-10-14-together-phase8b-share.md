# Together Phase 8b: Share-Sheet Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share a piece of text or a link from any app ("Dinner at Buka Sat 7pm", a booking-confirmation link) into Attune, and it opens a new Together event with that text ready. With Together's AI on, it goes into "Describe it" so one tap fills the form. Without AI, the first line becomes the title and the rest the note. Nothing is saved until you tap Save.

**Architecture:**
- **Native side:** `receive_sharing_intent` delivers shared text and URLs. On Android that's an `ACTION_SEND text/plain` filter on `MainActivity`; on iOS it's a Share Extension that hands off through the App Group `group.com.barsopus.attune` from Phase 8a and the `ShareMedia-com.barsopus.attune` URL scheme.
- **App side:**
  - A thin listener at the app root turns shares into a pending-share value and routes to `/together`.
  - The Together screen consumes the pending share once there's a relationship (after any sign-in or safety unlock) and opens the new-event sheet prefilled.
  - Pending shares expire after 10 minutes.
- **Scope:** text and links only, never images or files.

**Tech Stack:** Flutter 3.29, Riverpod 2, GoRouter, `receive_sharing_intent ^1.8.1`, the `xcodeproj` gem (`GEM_HOME=/opt/homebrew/lib/ruby/gems/3.4.0`), CocoaPods.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (D13 "share-sheet capture", §6.5 capture, §8.10 Phase 7 rulings, §8.11). Owner decisions (2026-10-14):
- Phase 8 pieces are off by default and discreet.
- The Android toolchain refresh comes first (done), then Phase 8.

## Global Constraints

- AI suggests; the person confirms. Sharing never saves anything by itself (D6, §8.10 R3).
- **Discreet:**
  - the share-sheet entry reads "Add to plans", with no Together or relationship wording;
  - nothing is shown outside the app;
  - shared content goes nowhere but the person's own form.
  - The entry's presence in the system share sheet is controlled by the OS; iOS users can hide it.
- AI capture runs only on tap, as in Phase 7. A share never spends AI budget by itself.
- Safety: a share opened while quick exit's safety unlock is pending waits behind the unlock. It opens only once Together is reachable, and it expires after 10 minutes.
- Owner rules:
  - work on `main`;
  - write each test first and watch it fail;
  - commit nothing unless asked;
  - re-read a file before editing it;
  - make surgical changes;
  - flag shared files (app root, `AndroidManifest.xml`, `Info.plist`, `Podfile`, the Xcode project).

### Rulings (record them in spec §8.12 in Task 6)

- **R1: Text and links only.** URLs arrive as text. There are no images or files, which keeps scope and privacy small.
- **R2: The shared text is clipped to 300 characters,** the AI capture limit.
  - With AI available it prefills "Describe it". The person taps Fill in, so no automatic AI spend.
  - Without AI, the first line, up to 120 characters, becomes the title and the remainder, up to 500, the note.
- **R3: One pending share at a time; the newest wins.** It's consumed once, when Together has a relationship, and expires after 10 minutes, so a share made before a sign-out or quick exit never pops up later.
- **R4: The entry is labelled "Add to plans"** (iOS extension display name; Android filter label), with no relationship wording.
- **R5: The iOS Share Extension reuses Phase 8a's App Group.** It's versioned via an xcconfig that includes both the Pods config and `Generated.xcconfig`, the same App Store version rule as the widget.

## Review Focus

1. **A share while signed out or behind quick exit's unlock.** It never opens the sheet before Together is reachable, and after 10 minutes it's dropped. Pinned in the Task 2 tests.
2. **A share with only an image, an empty string or whitespace** produces nothing. Pinned in the Task 1 tests.
3. **A 5,000-character pasted email** is clipped, and the title is the first line, at most 120 characters. Pinned in the Task 1 tests.
4. **Two shares in quick succession:** the second replaces the first, and nothing duplicates. Pinned in the Task 2 tests.
5. **Shares never trigger AI by themselves.** No `ai-together` call happens without a tap. Pinned in the Task 3 test.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `lib/features/together/domain/shared_capture.dart` | Create | `sharedCaptureText`, `SharedCaptureFallback` (pure) |
| `lib/features/together/data/share_intake.dart` | Create | `ShareSource` seam + `ReceiveSharingIntentSource` |
| `lib/features/together/presentation/together_providers.dart` | Modify | `pendingShareProvider` |
| `lib/features/together/presentation/widgets/share_intake_listener.dart` | Create | Root listener: share → pending → `/together` |
| `lib/app/…` (the app root widget that wraps the router) | Modify | Wrap with `ShareIntakeListener` (shared file) |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | Consume the pending share |
| `lib/features/together/presentation/widgets/couple_event_sheet.dart` | Modify | `initialText` parameter |
| `android/app/src/main/AndroidManifest.xml` | Modify | `SEND text/plain` filter labelled "Add to plans" |
| `ios/Share Extension/*`, `ios/Flutter/ShareExtension*.xcconfig`, `ios/Podfile`, `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj` | Create/Modify | The Share Extension |
| `docs/superpowers/specs/2026-10-14-together-hub-design.md` | Modify | §8.12 |

---

### Task 1: What a share becomes (pure Dart)

**Files:**
- Create: `lib/features/together/domain/shared_capture.dart`
- Test: `test/features/together/shared_capture_test.dart`

**Interfaces:**
- Produces:
  - `class SharedItem { final String kind; final String value; }`, where `kind` is `'text'`, `'url'` or other. It's a package-free mirror of `SharedMediaFile`.
  - `String? sharedCaptureText(List<SharedItem> items)`: the text and URL values joined by newlines, trimmed, clipped to 300 code points. It returns null if empty.
  - `({String title, String? note}) sharedCaptureFallback(String text)`: the first non-empty line, at most 120 characters, as the title; the rest, trimmed, at most 500, as the note, or null.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/together/domain/shared_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text and links become one capture note; images and blanks do not', () {
    expect(
      sharedCaptureText(const [
        SharedItem('text', '  Dinner at Buka Sat 7pm '),
        SharedItem('url', 'https://example.com/booking/123'),
      ]),
      'Dinner at Buka Sat 7pm\nhttps://example.com/booking/123',
    );
    expect(sharedCaptureText(const [SharedItem('image', '/tmp/a.jpg')]), isNull);
    expect(sharedCaptureText(const [SharedItem('text', '   ')]), isNull);
    expect(sharedCaptureText(const []), isNull);
  });

  test('a long paste is clipped to what capture accepts', () {
    final long = 'x' * 5000;
    expect(sharedCaptureText([SharedItem('text', long)])!.runes.length, 300);
  });

  test('without AI: first line is the title, the rest the note', () {
    final f = sharedCaptureFallback(
      '\nDinner at Buka\nSat 7pm, table for 2\nRef ABC123',
    );
    expect(f.title, 'Dinner at Buka');
    expect(f.note, 'Sat 7pm, table for 2\nRef ABC123');
    final one = sharedCaptureFallback('y' * 200);
    expect(one.title.length, 120);
    expect(one.note, isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/shared_capture_test.dart`
Expected: a compile failure because the file is missing.

- [ ] **Step 3: Write `shared_capture.dart`**

```dart
/// What a share from another app becomes (Together Phase 8b R1, R2).
library;

/// A shared item without the plugin's types (text, url, image, …).
class SharedItem {
  const SharedItem(this.kind, this.value);
  final String kind;
  final String value;
}

String _clip(String s, int max) {
  final r = s.runes;
  return r.length <= max ? s : String.fromCharCodes(r.take(max));
}

/// Text and links only, joined, trimmed, clipped to capture's 300.
String? sharedCaptureText(List<SharedItem> items) {
  final parts = [
    for (final i in items)
      if ((i.kind == 'text' || i.kind == 'url') && i.value.trim().isNotEmpty)
        i.value.trim(),
  ];
  if (parts.isEmpty) return null;
  return _clip(parts.join('\n'), 300);
}

/// Without AI: the first line is the title, the rest the note.
({String title, String? note}) sharedCaptureFallback(String text) {
  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return (title: '', note: null);
  final title = _clip(lines.first, 120);
  final rest = lines.skip(1).join('\n').trim();
  return (title: title, note: rest.isEmpty ? null : _clip(rest, 500));
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/shared_capture_test.dart`
Expected: 3 pass.

---

### Task 2: Receiving a share and holding it until Together is ready

**Files:**
- Create: `lib/features/together/data/share_intake.dart`
- Create: `lib/features/together/presentation/widgets/share_intake_listener.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Modify: the app root that hosts `MaterialApp.router`. Find it with `grep -rn "MaterialApp.router" lib`, then wrap the router child in `ShareIntakeListener`.
- Test: `test/features/together/share_intake_test.dart`

**Interfaces:**
- Produces:
  - `abstract class ShareSource { Future<List<SharedItem>> initial(); Stream<List<SharedItem>> stream(); Future<void> reset(); }`
  - `class ReceiveSharingIntentSource implements ShareSource`
  - `shareSourceProvider`: `Provider<ShareSource>`
  - `class PendingShare { final String text; final DateTime at; bool expiredAt(DateTime now) }`, which expires after 10 minutes.
  - `pendingShareProvider`: `StateProvider<PendingShare?>`
  - `ShareIntakeListener({required Widget child, required void Function() onShare})`. It listens for the initial share and the stream, sets the pending share (newest wins), resets the plugin, and calls `onShare`. The app root passes a callback that routes to `/together`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:attune/features/together/data/share_intake.dart';
import 'package:attune/features/together/domain/shared_capture.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/share_intake_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeShareSource implements ShareSource {
  FakeShareSource({this.first = const []});
  final List<SharedItem> first;
  final controller = StreamController<List<SharedItem>>.broadcast();
  int resets = 0;
  @override
  Future<List<SharedItem>> initial() async => first;
  @override
  Stream<List<SharedItem>> stream() => controller.stream;
  @override
  Future<void> reset() async => resets++;
}

Future<(ProviderContainer, List<int>)> _pump(
  WidgetTester t,
  FakeShareSource source,
) async {
  final opened = <int>[];
  final container = ProviderContainer(
    overrides: [shareSourceProvider.overrideWithValue(source)],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ShareIntakeListener(
          onShare: () => opened.add(1),
          child: const Text('app'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (container, opened);
}

void main() {
  testWidgets('a share that opened the app waits as a pending note', (t) async {
    final source = FakeShareSource(first: const [SharedItem('text', 'Dinner Sat 7pm')]);
    final (c, opened) = await _pump(t, source);
    expect(c.read(pendingShareProvider)?.text, 'Dinner Sat 7pm');
    expect(opened, [1]);
    expect(source.resets, 1);
  });

  testWidgets('a newer share replaces the older one; images are ignored', (t) async {
    final source = FakeShareSource();
    final (c, opened) = await _pump(t, source);
    source.controller.add(const [SharedItem('text', 'First')]);
    await t.pumpAndSettle();
    source.controller.add(const [SharedItem('text', 'Second')]);
    await t.pumpAndSettle();
    source.controller.add(const [SharedItem('image', '/tmp/x.jpg')]);
    await t.pumpAndSettle();
    expect(c.read(pendingShareProvider)?.text, 'Second');
    expect(opened.length, 2);
  });

  test('a pending share goes stale after 10 minutes', () {
    final p = PendingShare('x', DateTime(2026, 11, 2, 9));
    expect(p.expiredAt(DateTime(2026, 11, 2, 9, 9)), isFalse);
    expect(p.expiredAt(DateTime(2026, 11, 2, 9, 11)), isTrue);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/share_intake_test.dart`
Expected: a compile failure because the files are missing.

- [ ] **Step 3: Implement**
  - Run `flutter pub add receive_sharing_intent:^1.8.1`.
  - `share_intake.dart`:

```dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../domain/shared_capture.dart';

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

  @override
  Future<void> reset() async => ReceiveSharingIntent.instance.reset();
}
```

  Confirm that `SharedMediaType` has a `value` field (wire name) in 1.8.1's `lib/src/data/shared_media_file.dart`. If it doesn't, use `f.type.name`, and record that in the ledger.

  - The providers (`together_providers.dart`):

```dart
final shareSourceProvider = Provider<ShareSource>(
  (ref) => const ReceiveSharingIntentSource(),
);

/// A note shared from another app, waiting for Together (Phase 8b R3).
class PendingShare {
  const PendingShare(this.text, this.at);
  final String text;
  final DateTime at;

  bool expiredAt(DateTime now) =>
      now.difference(at) > const Duration(minutes: 10);
}

final pendingShareProvider = StateProvider<PendingShare?>((ref) => null);
```

  - `share_intake_listener.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/shared_capture.dart';
import '../together_providers.dart';

/// Turns a share from another app into a pending note and asks the app to
/// show Together (Phase 8b). Nothing is saved; nothing calls the AI.
class ShareIntakeListener extends ConsumerStatefulWidget {
  const ShareIntakeListener({super.key, required this.child, required this.onShare});
  final Widget child;
  final void Function() onShare;

  @override
  ConsumerState<ShareIntakeListener> createState() => _ShareIntakeListenerState();
}

class _ShareIntakeListenerState extends ConsumerState<ShareIntakeListener> {
  StreamSubscription<List<SharedItem>>? _sub;

  @override
  void initState() {
    super.initState();
    final source = ref.read(shareSourceProvider);
    _sub = source.stream().listen(_take, onError: (_) {});
    source.initial().then(_take).catchError((_) {});
  }

  void _take(List<SharedItem> items) {
    final text = sharedCaptureText(items);
    if (text == null || !mounted) return;
    ref.read(pendingShareProvider.notifier).state = PendingShare(text, DateTime.now());
    ref.read(shareSourceProvider).reset().catchError((_) {});
    widget.onShare();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

  - The app root: wrap the router's child (or `MaterialApp.router`'s `builder` child) in `ShareIntakeListener(onShare: () => router.go(RouteNames.together), child: …)`. Use the existing router instance variable. Record the exact file in the ledger. This is a shared file, so add one wrapper and nothing else.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/share_intake_test.dart && flutter analyze lib/features/together lib/app`
Expected: 3 pass; no issues. Other widget tests that pump the app root (`grep -rln "createAppRouter\|AttuneApp" test`) must still pass. The real `ReceiveSharingIntentSource` would hit a missing channel in tests, but its errors are caught. If a harness fails, override `shareSourceProvider` there with a `FakeShareSource()` and record that in the ledger.

---

### Task 3: Together opens the shared note, prefilled

**Files:**
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart` (an `initialText` parameter)
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (consume the pending share)
- Test: `test/features/together/together_screen_test.dart`, `test/features/together/couple_event_sheet_test.dart`

**Interfaces:**
- Produces: `showCoupleEventSheet(…, String? initialText)`. With AI available, it prefills "Describe it"; otherwise the title and note come from `sharedCaptureFallback`.

- [ ] **Step 1: Write the failing tests**
  - In `couple_event_sheet_test.dart`, give `_open` an optional `String? text` that's passed as `initialText`:

```dart
  testWidgets('a shared note waits in Describe it; nothing is read until I tap', (
    t,
  ) async {
    final ai = FakeAiGateway(response: {'draft': {}});
    await _open(t, ai: ai, text: 'Dinner at Buka Sat 7pm');
    expect(find.text('Dinner at Buka Sat 7pm'), findsOneWidget);
    expect(ai.bodies, isEmpty);
  });

  testWidgets('without AI, a shared note fills the title and note', (t) async {
    await _open(t, text: 'Dinner at Buka\nSat 7pm, table for 2');
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Sat 7pm, table for 2'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sat 7pm, table for 2'), findsOneWidget);
  });
```

  - In `together_screen_test.dart`:

```dart
  testWidgets('a pending share opens the new-event sheet once, then clears', (
    t,
  ) async {
    await _pump(t);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    c.read(pendingShareProvider.notifier).state = PendingShare(
      'Picnic Sun',
      DateTime.now(),
    );
    await t.pumpAndSettle();
    expect(find.text('New event'), findsOneWidget);
    expect(c.read(pendingShareProvider), isNull);
  });

  testWidgets('a stale share is dropped quietly', (t) async {
    await _pump(t);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    c.read(pendingShareProvider.notifier).state = PendingShare(
      'Old',
      DateTime.now().subtract(const Duration(minutes: 11)),
    );
    await t.pumpAndSettle();
    expect(find.text('New event'), findsNothing);
    expect(c.read(pendingShareProvider), isNull);
  });
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/together/couple_event_sheet_test.dart test/features/together/together_screen_test.dart`
Expected: a compile failure (`initialText`, the provider), then failures because the sheet isn't shown.

- [ ] **Step 3: Implement**
  - **Event sheet:** add `String? initialText` through `showCoupleEventSheet` and the widget.
    - In `initState`, for a new event: `if (widget.initialText != null) _describe.text = widget.initialText!;`.
    - In `build`, when `aiOn` is false, apply the text as the title and note once only (keep a `bool _fallbackApplied` flag), using `sharedCaptureFallback`.
    - The non-AI path must also apply when availability resolves to `false` after the first frame. Apply it the first time `aiOn` is known `false` (`valueOrNull == false`), so a loading frame doesn't count.
  - **Hub:** in `together_screen.dart`'s `build`, after `relationshipId` is known, add:

```dart
    ref.listen<PendingShare?>(pendingShareProvider, (_, share) {
      if (share == null) return;
      final id = ref.read(timeline_providers.currentRelationshipIdProvider).valueOrNull;
      if (id == null) return; // waits until Together is reachable (R3)
      ref.read(pendingShareProvider.notifier).state = null;
      if (share.expiredAt(DateTime.now())) return;
      showCoupleEventSheet(context, relationshipId: id, initialText: share.text);
    });
```

    Also consume a share that was already pending before the hub mounted: in the post-frame zone-report microtask, read `pendingShareProvider` and apply the same logic. Import `../widgets/couple_event_sheet.dart` (already imported) and `../../domain/shared_capture.dart` if needed.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 4: Android share target

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` (inside the `MainActivity` `<activity>`)

- [ ] **Step 1: Add the filter**

```xml
            <!-- Share text or a link into Together (Phase 8b): "Add to plans". -->
            <intent-filter android:label="Add to plans">
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
```

- [ ] **Step 2: Verify**

Run: `xmllint --noout android/app/src/main/AndroidManifest.xml && flutter build apk --debug --target-platform android-arm64`
Expected: valid XML, then `Built …/app-debug.apk`. Check that `MainActivity`'s `launchMode` is `singleTop` (or `singleTask`) so a share to the running app reaches the stream, not a second instance. If it isn't, record that in the ledger. The plugin documents `singleTask`; change it only if it's missing, since it's a shared setting.

---

### Task 5: iOS Share Extension

**Files:**
- Create: `ios/Share Extension/ShareViewController.swift`, `ios/Share Extension/Base.lproj/MainInterface.storyboard`, `ios/Share Extension/Info.plist`, `ios/Share Extension/Share Extension.entitlements`
- Create: `ios/Flutter/ShareExtension-Debug.xcconfig`, `ios/Flutter/ShareExtension-Release.xcconfig`
- Modify: `ios/Podfile`, `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj` (script)

- [ ] **Step 1: The extension files**

`ShareViewController.swift`:

```swift
// "Add to plans" (Together Phase 8b): hands shared text/links to Attune,
// which opens a new event to review. Nothing is saved here.
import receive_sharing_intent

class ShareViewController: RSIShareViewController {}
```

  - `Base.lproj/MainInterface.storyboard`: copy `~/.pub-cache/hosted/pub.dev/receive_sharing_intent-1.8.1/example/ios/Share Extension/Base.lproj/MainInterface.storyboard` as is. Its `customClass` is `ShareViewController`, with `customModuleProvider="target"`.
  - `Info.plist`: the package's README template, with these changes:
    - `AppGroupId` is the literal `group.com.barsopus.attune`;
    - `CFBundleDisplayName` is `Add to plans`;
    - `CFBundleShortVersionString` is `$(MARKETING_VERSION)` and `CFBundleVersion` is `$(CURRENT_PROJECT_VERSION)`;
    - the `NSExtensionActivationRule` keeps only `NSExtensionActivationSupportsText` = true and `NSExtensionActivationSupportsWebURLWithMaxCount` = 1;
    - `PHSupportedMediaTypes` is removed (no images or video, R1).
  - `Share Extension.entitlements`: the App Group `group.com.barsopus.attune`, the same as the widget's.

- [ ] **Step 2: Versioned config that coexists with Pods**

`ios/Flutter/ShareExtension-Debug.xcconfig`:

```
#include? "../Pods/Target Support Files/Pods-Share Extension/Pods-Share Extension.debug.xcconfig"
#include "Generated.xcconfig"
MARKETING_VERSION = $(FLUTTER_BUILD_NAME)
CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)
```

  `ShareExtension-Release.xcconfig` is the same, with `release` in the Pods path. The Profile configuration uses the release one.

- [ ] **Step 3: Add the target** (`<scratchpad>/add_share_extension.rb`, run with `GEM_HOME=/opt/homebrew/lib/ruby/gems/3.4.0 ruby …` from the repo root)

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
abort('Share Extension already exists') if project.targets.any? { |t| t.name == 'Share Extension' }
runner = project.targets.find { |t| t.name == 'Runner' }

ext = project.new_target(:app_extension, 'Share Extension', :ios, '14.0')
group = project.main_group.new_group('Share Extension', 'Share Extension')
ext.add_file_references([group.new_reference('ShareViewController.swift')])
storyboard = group.new_variant_group('MainInterface.storyboard')
storyboard.new_reference('Base.lproj/MainInterface.storyboard').name = 'Base'
ext.resources_build_phase.add_file_reference(storyboard)
group.new_reference('Info.plist')
group.new_reference('Share Extension.entitlements')

flutter = project.main_group.find_subpath('Flutter')
debug_xc = flutter.new_reference('ShareExtension-Debug.xcconfig')
release_xc = flutter.new_reference('ShareExtension-Release.xcconfig')

ext.build_configurations.each do |c|
  c.base_configuration_reference = c.name == 'Debug' ? debug_xc : release_xc
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.barsopus.attune.ShareExtension'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'Share Extension/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'Share Extension/Share Extension.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = 'A8RJ357U9Y'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

runner.add_dependency(ext)
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
abort('missing Embed Foundation Extensions (Phase 8a)') unless embed
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
puts 'Share Extension added'
```

- [ ] **Step 4: Podfile and Runner Info.plist**
  - In `ios/Podfile`, inside `target 'Runner' do`, add the extension target. Its pod is needed for `RSIShareViewController`.

```ruby
  # "Add to plans" share extension (Together Phase 8b).
  target 'Share Extension' do
    inherit! :search_paths
  end
```

  - In `ios/Runner/Info.plist`:
    - add `<key>AppGroupId</key><string>group.com.barsopus.attune</string>`;
    - add a second dict to the existing `CFBundleURLTypes` array with `CFBundleTypeRole` `Editor` and `CFBundleURLSchemes` `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`;
    - leave the existing `attune` scheme untouched.

- [ ] **Step 5: Build**

Run: `cd ios && pod install && cd .. && flutter build ios --simulator --debug`
Expected:
- `Built …/Runner.app`;
- `Runner.app/PlugIns/Share Extension.appex` exists, carrying the app's version and build: extend `check_appex_version.sh` to check both appexes;
- `plutil -p` shows `com.apple.share-services`.

If linking `RSIShareViewController` fails with search paths only, change the Podfile entry to `inherit! :complete`, or add `pod 'receive_sharing_intent', :path => '.symlinks/plugins/receive_sharing_intent/ios'` inside the extension target, and record that in the ledger. If CocoaPods warns about the base configuration, the `#include?` in our xcconfig already pulls in the Pods settings; check that `OTHER_LDFLAGS` includes the framework.

---

### Task 6: Spec rulings, full verification, device checklist

- [ ] **Step 1: Add §8.12** after §8.11:

```markdown
### 8.12 Phase 8b rulings — share-sheet capture (plan `2026-10-14-together-phase8b-share.md`)
- R1: Text and links only; no images or files.
- R2: Clipped to 300 characters; with AI it waits in "Describe it" (no AI call until tapped); without AI the first line is the title and the rest the note.
- R3: One pending share, newest wins, opened once when Together is reachable; dropped after 10 minutes.
- R4: The share-sheet entry reads "Add to plans".
- R5: The iOS extension shares the widget's App Group and carries the app's version.
```

- [ ] **Step 2: Full verification**

Run:
- `flutter test`
- `flutter analyze lib`
- `flutter build apk --debug --target-platform android-arm64`
- `flutter build ios --simulator --debug`
- the appex version check

Expected: everything passes.

- [ ] **Step 3: Owner device checklist** (in the report):
  1. **Android:** in Notes, share some text, then pick "Add to plans". Attune should open a new event with it.
  2. **iOS:** on a device with the App Group enabled for `com.barsopus.attune.ShareExtension` as well, share text from Notes, then pick "Add to plans". It should behave the same way.
  3. **Signed out, or after quick exit:** sharing must not show the event until you're back in and Together opens. After 10 minutes the share is dropped.
