import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// One web link found inside a message body.
class DetectedLink {
  const DetectedLink({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });

  /// Code-unit range in the source string, [start, end).
  final int start;
  final int end;

  /// Exactly what the person typed (shown as the link text).
  final String text;

  /// What gets launched: http/https only; `www.` is given `https://`.
  final Uri uri;

  /// What "Copy link" puts on the clipboard: the link as typed (never
  /// [uri]'s percent-encoded form), with `https://` before a `www.` link.
  String get copyText =>
      text.toLowerCase().startsWith('www.') ? 'https://$text' : text;
}

/// http://, https:// and www. links. Bare domains are NOT linked (too many
/// false positives: "e.g.", "file.txt"), nor are other schemes — the only
/// thing a tap can ever launch here is a web URL. The leading `\b` keeps a
/// "www." in the middle of a word ("awww.") from becoming a link.
/// Parentheses are allowed (Wikipedia's `Foo_(bar)`); an unbalanced closing
/// one is trimmed afterwards, so "(see https://x.io/a)" still ends at `a`.
final RegExp _linkPattern = RegExp(
  r'\b(?:https?:\/\/|www\.)[^\s<>\[\]{}"'
  "'"
  r']+',
  caseSensitive: false,
);

/// Sentence punctuation and emphasis markers ("*https://x.io*") that end a
/// sentence rather than the link.
const String _trailingPunctuation = '.,;:!?*_~';

/// Whether [text]'s last character is a `)` with no `(` to match it.
bool _endsWithUnbalancedParen(String text) {
  if (!text.endsWith(')')) return false;
  var depth = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0x28) depth++;
    if (unit == 0x29) depth--;
  }
  return depth < 0;
}

bool _isWebScheme(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

List<DetectedLink> detectLinks(String text) {
  final links = <DetectedLink>[];
  for (final match in _linkPattern.allMatches(text)) {
    var end = match.end;
    while (end > match.start) {
      final last = text[end - 1];
      if (_trailingPunctuation.contains(last) ||
          (last == ')' &&
              _endsWithUnbalancedParen(text.substring(match.start, end)))) {
        end--;
      } else {
        break;
      }
    }
    final raw = text.substring(match.start, end);
    final isWww = raw.toLowerCase().startsWith('www.');
    // "www." with nothing after it (the dot was trimmed as punctuation).
    if (isWww && raw.length <= 4) continue;
    final uri = Uri.tryParse(isWww ? 'https://$raw' : raw);
    if (uri == null || !_isWebScheme(uri) || uri.host.isEmpty) continue;
    links.add(DetectedLink(start: match.start, end: end, text: raw, uri: uri));
  }
  return links;
}

typedef LinkLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

Future<bool> _defaultLauncher(
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) => launchUrl(uri, mode: mode);

/// Opens a web link in the external browser. Refuses anything that is not
/// http/https (nothing a message can contain should ever reach `tel:`,
/// `javascript:`, `file:`, `intent:` or an app scheme through this path).
/// canLaunchUrl is skipped on purpose: it is unreliable on Android 11+
/// without `<queries>`, and launchUrl's own false/throw is the honest signal.
Future<void> openMessageLink(
  BuildContext context,
  Uri uri, {
  LinkLauncher? launcher,
}) async {
  if (!_isWebScheme(uri) || uri.host.isEmpty) return;
  final launch = launcher ?? _defaultLauncher;
  var ok = false;
  try {
    ok = await launch(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    context.showErrorSnackbar("Couldn't open that link.");
  }
}

/// Message text with web links underlined and tappable. Recognizers are
/// owned here and disposed with the State, so a recycled list row never
/// leaks them.
///
/// Only a tap recognizer sits on a link: the bubble's own long-press keeps
/// routing to the focused message menu (which offers "Copy link").
class LinkifiedMessageText extends StatefulWidget {
  const LinkifiedMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    this.onOpenLink,
  });

  final String text;
  final TextStyle? style;
  final Color linkColor;

  /// Defaults to [openMessageLink] when null.
  final void Function(Uri uri)? onOpenLink;

  @override
  State<LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<LinkifiedMessageText> {
  /// The links in [LinkifiedMessageText.text] and one recognizer each, built
  /// when the text changes — never per build. A rebuild mid-tap (the list
  /// rebuilds every frame while its bottom reserve glides) keeps the
  /// recognizer the pointer went down on, so the tap still lands.
  List<DetectedLink> _links = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _syncLinks();
  }

  @override
  void didUpdateWidget(covariant LinkifiedMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _syncLinks();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _syncLinks() {
    _disposeRecognizers();
    _links = detectLinks(widget.text);
    for (final link in _links) {
      _recognizers.add(
        TapGestureRecognizer()
          // Reads the current widget at tap time, so a new onOpenLink with
          // the same text is honoured without rebuilding the recognizer.
          ..onTap = () {
            final open = widget.onOpenLink;
            if (open != null) {
              open(link.uri);
            } else {
              openMessageLink(context, link.uri);
            }
          },
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    if (links.isEmpty) {
      return Text.rich(TextSpan(text: widget.text), style: widget.style);
    }

    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      if (link.start > cursor) {
        children.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      // No semanticsLabel: the tap recognizer already gives the span its
      // link role, and a label would also change the paragraph's text.
      children.add(
        TextSpan(
          text: link.text,
          style: linkStyle,
          recognizer: _recognizers[i],
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return Text.rich(TextSpan(children: children), style: widget.style);
  }
}
