import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/linkified_message_text.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/chat_test_harness.dart';

void main() {
  group('detectLinks', () {
    test('finds http, https and www links and strips trailing punctuation', () {
      final links = detectLinks(
        'see https://maps.app.goo.gl/abc, or http://x.io/p?q=1). '
        'also www.example.com/path!',
      );
      expect(links.map((l) => l.text), [
        'https://maps.app.goo.gl/abc',
        'http://x.io/p?q=1',
        'www.example.com/path',
      ]);
      expect(links[2].uri.toString(), 'https://www.example.com/path');
      expect(links[0].start, 4);
    });

    test('ignores bare domains and non-web schemes', () {
      expect(detectLinks('e.g. example.com or file.txt'), isEmpty);
      expect(detectLinks('javascript:alert(1) ftp://host/x'), isEmpty);
    });

    test('never yields a launchable non-web scheme', () {
      const hostile =
          'file:///etc/passwd intent://scan/#Intent;scheme=zxing;end '
          'attune://settings data:text/html,hi JAVASCRIPT:alert(1) '
          'mailto:a@b.co tel:+233240000000 sms:+1 market://details?id=x';
      expect(detectLinks(hostile), isEmpty);
    });

    test('keeps balanced parentheses, trims an unbalanced closing one', () {
      expect(
        detectLinks('read https://en.wikipedia.org/wiki/Foo_(bar) first')
            .single
            .text,
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
      expect(
        detectLinks('(see https://en.wikipedia.org/wiki/Foo_(bar))').single.text,
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
      expect(detectLinks('(see https://x.io/a).').single.text, 'https://x.io/a');
      expect(
        detectLinks('https://x.io/p?q=(1)&r=2, ok').single.text,
        'https://x.io/p?q=(1)&r=2',
      );
    });

    test('trims emphasis markers typed around a link', () {
      expect(detectLinks('*https://x.io/b*').single.text, 'https://x.io/b');
      expect(detectLinks('~https://x.io/c~!').single.text, 'https://x.io/c');
      expect(detectLinks('https://x.io/d__').single.text, 'https://x.io/d');
      expect(
        detectLinks('https://x.io/snake_case_path').single.text,
        'https://x.io/snake_case_path',
      );
    });

    test('copies what was typed, not the percent-encoded form', () {
      final links = detectLinks('https://example.com/café and www.x.io/ü');
      expect(links[0].uri.toString(), 'https://example.com/caf%C3%A9');
      expect(links[0].copyText, 'https://example.com/café');
      expect(links[1].copyText, 'https://www.x.io/ü');
    });

    test('does not link "www." in the middle of a word or with no host', () {
      expect(detectLinks('awww.example.com'), isEmpty);
      expect(detectLinks('just www. and http:// alone'), isEmpty);
    });
  });

  group('openMessageLink', () {
    testWidgets('launches http(s) externally and refuses other schemes', (
      tester,
    ) async {
      final launched = <Uri>[];
      Future<bool> fakeLauncher(
        Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        expect(mode, LaunchMode.externalApplication);
        launched.add(uri);
        return true;
      }

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await openMessageLink(
        ctx,
        Uri.parse('https://example.com/a'),
        launcher: fakeLauncher,
      );
      await openMessageLink(
        ctx,
        Uri.parse('javascript:alert(1)'),
        launcher: fakeLauncher,
      );
      await openMessageLink(
        ctx,
        Uri.parse('tel:+233240000000'),
        launcher: fakeLauncher,
      );
      for (final hostile in [
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'attune://settings',
        'mailto:a@b.co',
        'data:text/html,hi',
        'market://details?id=x',
      ]) {
        await openMessageLink(ctx, Uri.parse(hostile), launcher: fakeLauncher);
      }
      expect(launched.map((u) => u.toString()), ['https://example.com/a']);
    });

    testWidgets('a launcher that returns false shows a warm error', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        // The app snackbar sizes itself through ScreenUtil.
        withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await openMessageLink(
        ctx,
        Uri.parse('https://example.com/a'),
        launcher:
            (uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
                false,
      );
      await tester.pump();
      expect(find.text("Couldn't open that link."), findsOneWidget);
    });
  });

  group('LinkifiedMessageText', () {
    testWidgets('renders links as tappable spans and wraps a long URL', (
      tester,
    ) async {
      final opened = <Uri>[];
      final longUrl = 'https://example.com/${'a' * 300}';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: LinkifiedMessageText(
                text: 'look $longUrl now',
                style: const TextStyle(fontSize: 16),
                linkColor: Colors.blue,
                onOpenLink: opened.add,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');

      final rich = tester.widget<Text>(find.byType(Text));
      final root = rich.textSpan! as TextSpan;
      final linkSpans = <TextSpan>[];
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          linkSpans.add(span);
        }
        return true;
      });
      expect(linkSpans, hasLength(1));
      expect(linkSpans.single.style?.decoration, TextDecoration.underline);
      (linkSpans.single.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened.single.toString(), longUrl);

      final size = tester.getSize(find.byType(Text));
      expect(size.height, greaterThan(40), reason: 'the URL wrapped');
    });

    testWidgets('a link reads as the typed text (no "Link:" prefix)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkifiedMessageText(
              text: 'menu at www.example.com/menu tonight',
              style: TextStyle(fontSize: 16),
              linkColor: Colors.blue,
            ),
          ),
        ),
      );
      // The recognizer alone gives the span its link role; a semantics
      // label would also change the paragraph's plain text.
      expect(find.text('menu at www.example.com/menu tonight'), findsOneWidget);
    });

    testWidgets('a rebuild with the same text keeps its recognizers, so a '
        'tap that spans the rebuild still opens', (tester) async {
      final opened = <Uri>[];
      Widget build(double fontSize) => MaterialApp(
        home: Scaffold(
          body: LinkifiedMessageText(
            text: 'https://example.com/x',
            style: TextStyle(fontSize: fontSize),
            linkColor: Colors.blue,
            onOpenLink: opened.add,
          ),
        ),
      );
      TapGestureRecognizer recognizer() {
        final root =
            tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
        TapGestureRecognizer? found;
        root.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            found = span.recognizer! as TapGestureRecognizer;
          }
          return true;
        });
        return found!;
      }

      await tester.pumpWidget(build(16));
      final first = recognizer();
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(Text)) + const Offset(20, 8),
      );
      await tester.pumpWidget(build(16.5));
      expect(identical(recognizer(), first), isTrue);
      await gesture.up();
      await tester.pump();
      expect(opened.map((u) => u.toString()), ['https://example.com/x']);
    });

    testWidgets('new text gets new recognizers', (tester) async {
      Widget build(String text) => MaterialApp(
        home: Scaffold(
          body: LinkifiedMessageText(
            text: text,
            style: const TextStyle(fontSize: 16),
            linkColor: Colors.blue,
          ),
        ),
      );
      int linkSpans() {
        final root =
            tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
        var n = 0;
        root.visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) n++;
          return true;
        });
        return n;
      }

      await tester.pumpWidget(build('https://a.io'));
      expect(linkSpans(), 1);
      await tester.pumpWidget(build('https://a.io and https://b.io'));
      expect(linkSpans(), 2);
      await tester.pumpWidget(build('no links'));
      expect(linkSpans(), 0);
    });

    testWidgets('plain text has no recognizers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkifiedMessageText(
              text: 'no links here',
              style: TextStyle(fontSize: 16),
              linkColor: Colors.blue,
            ),
          ),
        ),
      );
      final rich = tester.widget<Text>(find.byType(Text));
      final root = rich.textSpan! as TextSpan;
      var recognizers = 0;
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) recognizers++;
        return true;
      });
      expect(recognizers, 0);
    });
  });

  group('inside a real MessageBubble', () {
    // Review Focus pin: the bubble wraps its body in two IntrinsicWidth
    // layers (the row's Align and _BubbleBody's Column). An unbroken
    // 300-character URL must still wrap inside them at phone width, with no
    // overflow, and a real tap on the wrapped link must still open it.
    testWidgets('a 300-char URL wraps at 390 px and opens on tap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final launched = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        }
        if (call.method == 'canLaunch') return true;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final longUrl = 'https://example.com/${'a' * 280}';
      expect(longUrl.length, 300);
      final message = Message(
        id: 'm-link',
        clientMessageId: 'c-link',
        relationshipId: 'r1',
        senderId: 'partner',
        content: 'look $longUrl now',
        createdAt: DateTime(2026, 7, 1, 15, 5),
        status: MessageStatus.delivered,
        isMine: false,
      );

      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(home: Scaffold(body: MessageBubble(message: message))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow');

      final linkified = find.byType(LinkifiedMessageText);
      expect(linkified, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: linkified, matching: find.byType(RichText)),
      );
      final box = tester.getRect(linkified);
      expect(box.width, lessThanOrEqualTo(390));
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        greaterThan(box.width),
        reason: 'the URL is wider than the bubble, so it had to wrap',
      );
      expect(box.height, greaterThan(16 * 1.2 * 3), reason: 'several lines');

      // Tap the middle of the URL, which sits on a wrapped line.
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 160, extentOffset: 161),
      );
      expect(boxes, isNotEmpty);
      final glyph = boxes.first.toRect();
      expect(glyph.top, greaterThan(0), reason: 'not the first line');
      await tester.tapAt(paragraph.localToGlobal(glyph.center));
      await tester.pump();
      expect(launched, [longUrl]);
    });
  });
}
