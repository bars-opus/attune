import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/data_export/data/data_export_service.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _intro =
    "A copy of what's yours: your messages and the photos you shared, plans, "
    'calendar, stories, check-ins, journal, quiz answers, and the insights '
    'and readouts Attune showed you. Never anything about safety, and never '
    'the behind-the-scenes analysis of your chats.';

Future<void> _launch(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Settings -> Download my data (Spec 3c).
class DataExportScreen extends ConsumerStatefulWidget {
  const DataExportScreen({
    super.key,
    this.pollEvery = const Duration(seconds: 10),
    this.openUrl = _launch,
    this.now = DateTime.now,
    this.confirmPin = confirmSafetyPin,
  });

  static const routeName = '/settings/download-my-data';

  final Duration pollEvery;
  final Future<void> Function(String url) openUrl;
  final DateTime Function() now;

  /// With a Safety PIN set, preparing or downloading asks for it (plan
  /// review I8).
  final Future<bool> Function(BuildContext context) confirmPin;

  @override
  ConsumerState<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends ConsumerState<DataExportScreen> {
  DataExportStatus? _status;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Timer? _poll;

  // One PIN and one set of links per visit (re-review M3). The links last
  // 15 minutes; they are fetched again after 10, or for another download.
  bool _pinConfirmed = false;
  List<String>? _urls;
  String? _urlsFor;
  DateTime? _urlsAt;

  DataExportService get _service => ref.read(dataExportServiceProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await _service.latest();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loaded = true;
      });
      _poll?.cancel();
      if (s?.inProgress ?? false) {
        _poll = Timer(widget.pollEvery, _refresh);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<bool> _confirmOnce() async {
    if (_pinConfirmed) return true;
    _pinConfirmed = await widget.confirmPin(context);
    return _pinConfirmed;
  }

  Future<void> _request() async {
    if (!await _confirmOnce() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.request();
    } on DataExportException catch (e) {
      // Too soon or already running: the refreshed status says when
      // (final review I4).
      if (e.reason == ExportRefusal.other) {
        _error = "Couldn't prepare it. Try again.";
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  Future<void> _download(int part, String downloadKey) async {
    if (!await _confirmOnce() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh =
          _urlsAt != null &&
          widget.now().difference(_urlsAt!) < const Duration(minutes: 10);
      if (_urls == null || _urlsFor != downloadKey || !fresh) {
        _urls = await _service.downloadUrls();
        _urlsFor = downloadKey;
        _urlsAt = widget.now();
      }
      final urls = _urls!;
      await widget.openUrl(urls[part.clamp(0, urls.length - 1)]);
    } catch (_) {
      _error = "Couldn't open the download. Try again.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime? at) =>
      at == null ? '' : MyDateFormat.toDate(at.toLocal());

  /// A pause ends within a day: then the time is what matters (re-review M2).
  String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = widget.now().toLocal();
    if (local.difference(now) >= const Duration(hours: 24)) return _date(at);
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? MyDateFormat.toTime(local)
        : MyDateFormat.join([
          MyDateFormat.toDateShort(local),
          MyDateFormat.toTime(local),
        ]);
  }

  bool _waitingUntil(DateTime? at) => at != null && at.isAfter(widget.now());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = _status;
    final children = <Widget>[
      Text(
        _intro,
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      Gap(Spacing.md.h),
      SemanticContainerWidget(
        title: 'Keep it somewhere private',
        content:
            'The download holds your journal, check-ins and messages. Save it '
            'where only you can open it, not on a shared device or folder.',
        icon: Icons.lock_outline,
        backgroundColor: scheme.warning.withValues(alpha: 0.1),
        borderColor: scheme.warning,
        iconColor: scheme.warning,
        textTheme: text,
      ),
      Gap(Spacing.lg.h),
    ];
    Widget prepare(String label) => FilledButton(
      onPressed: _busy ? null : _request,
      child: Text(label),
    );
    List<Widget> downloads(int count, DateTime? until) {
      final parts = count.clamp(1, 99);
      final key = '${until?.toIso8601String()}|$parts';
      return [
        for (var i = 0; i < parts; i++) ...[
          FilledButton(
            onPressed: _busy ? null : () => _download(i, key),
            child: Text(
              parts == 1 ? 'Download' : 'Download part ${i + 1} of $parts',
            ),
          ),
          Gap(Spacing.sm.h),
        ],
      ];
    }

    // While a new one is not ready, the earlier one still is (re-review M8).
    List<Widget> earlier() =>
        s == null || (s.earlierParts ?? 0) < 1
            ? const []
            : [
              Gap(Spacing.lg.h),
              Text(
                'Your earlier download is ready until ${_date(s.earlierExpiresAt)}.',
                style: text.bodyLarge,
              ),
              Gap(Spacing.md.h),
              ...downloads(s.earlierParts!, s.earlierExpiresAt),
            ];

    if (!_loaded) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (s != null && s.inProgress) {
      children.add(
        Text(
          'Getting it ready… you can leave this screen.',
          style: text.bodyLarge,
        ),
      );
      children.addAll(earlier());
    } else if (s != null && s.state == ExportState.ready) {
      children.addAll([
        Text('Ready until ${_date(s.expiresAt)}.', style: text.bodyLarge),
        Gap(Spacing.md.h),
        ...downloads(s.parts ?? 1, s.expiresAt),
        if (_waitingUntil(s.nextAllowedAt))
          Text(
            'You can ask for a new one after ${_when(s.nextAllowedAt)}.',
            style: text.bodySmall,
          )
        else
          OutlinedButton(
            onPressed: _busy ? null : _request,
            child: const Text('Prepare a new one'),
          ),
      ]);
    } else if (s != null && s.state == ExportState.failed) {
      if (_waitingUntil(s.nextAllowedAt)) {
        children.add(
          Text(
            "Couldn't prepare it. You can try again after ${_when(s.nextAllowedAt)}.",
            style: text.bodyLarge,
          ),
        );
      } else {
        children.addAll([
          Text("Couldn't prepare it. Try again.", style: text.bodyLarge),
          Gap(Spacing.md.h),
          prepare('Try again'),
        ]);
      }
      children.addAll(earlier());
    } else {
      if (s != null && s.state == ExportState.expired) {
        children.addAll([
          Text('Your last download has expired.', style: text.bodyLarge),
          Gap(Spacing.md.h),
        ]);
      }
      if (s != null && _waitingUntil(s.nextAllowedAt)) {
        children.add(
          Text(
            'You can ask for a new one after ${_when(s.nextAllowedAt)}.',
            style: text.bodyLarge,
          ),
        );
      } else {
        children.add(prepare('Prepare my download'));
      }
      children.addAll(earlier());
    }
    if (_error != null) {
      children.addAll([
        Gap(Spacing.sm.h),
        Text(
          _error!,
          style: text.bodySmall?.copyWith(color: scheme.error),
        ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Download my data')),
      body: ListView(padding: EdgeInsets.all(Spacing.lg.w), children: children),
    );
  }
}
