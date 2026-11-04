import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the Opinions content filter refused a post, comment or edit
/// (Spec 1 §4.3 W9a): the writer RPCs raise `content:<wire>`.
enum ContentFilterReason {
  contactInfo('contact_info', ClientMetricKey.opinionBlockedContactInfo),
  slur('slur', ClientMetricKey.opinionBlockedSlur),
  explicit('explicit', ClientMetricKey.opinionBlockedExplicit);

  const ContentFilterReason(this.wire, this.metric);

  final String wire;

  /// The count the app keeps (`opinion_blocked:<wire>`); nothing else about
  /// a blocked post is stored anywhere (§4.8).
  final ClientMetricKey metric;

  /// The refusal in [error], or null when [error] is anything else (which
  /// keeps today's handling).
  static ContentFilterReason? of(Object error) {
    if (error is! PostgrestException) return null;
    for (final r in values) {
      if (error.message == 'content:${r.wire}') return r;
    }
    return null;
  }

  /// The inline line shown under the field (§8 W9a); the draft stays.
  String message(AppLocalizations loc) => switch (this) {
    ContentFilterReason.contactInfo => loc.opinions_filterContactInfo,
    ContentFilterReason.slur => loc.opinions_filterSlur,
    ContentFilterReason.explicit => loc.opinions_filterExplicit,
  };
}

/// Which part of a post the filter refused (batch-3 review I-3): the writer
/// RPCs name a reply's quoted text or a poll option in the refusal's HINT;
/// the writer's own text carries none.
enum ContentFilterPart {
  text(null),
  quotedText('quoted_text'),
  pollOption('poll_option');

  const ContentFilterPart(this.hint);

  final String? hint;

  /// The part [error] names; [text] for anything else.
  static ContentFilterPart of(Object error) {
    if (error is PostgrestException) {
      for (final p in values) {
        if (p.hint != null && error.hint == p.hint) return p;
      }
    }
    return ContentFilterPart.text;
  }

  /// The lines shown for [reason] refused in this part. A refused quote
  /// replaces the reason (the writer's own words passed: the server checks
  /// them first, and the quote isn't theirs to take out); a poll option
  /// adds where it is.
  List<String> lines(ContentFilterReason reason, AppLocalizations loc) =>
      switch (this) {
        ContentFilterPart.text => [reason.message(loc)],
        ContentFilterPart.quotedText => [loc.opinions_filterQuoted],
        ContentFilterPart.pollOption => [
          reason.message(loc),
          loc.opinions_filterPollOption,
        ],
      };
}
