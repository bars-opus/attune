import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiet_states/data/hidden_periods_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<DateTimeRange?> _defaultPick(BuildContext context) =>
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

/// Settings -> Hide a period (Spec 7, B9 (d)).
class HiddenPeriodsScreen extends ConsumerStatefulWidget {
  const HiddenPeriodsScreen({super.key, this.pickRange = _defaultPick});

  static const routeName = '/settings/hidden-periods';

  final Future<DateTimeRange?> Function(BuildContext context) pickRange;

  @override
  ConsumerState<HiddenPeriodsScreen> createState() =>
      _HiddenPeriodsScreenState();
}

class _HiddenPeriodsScreenState extends ConsumerState<HiddenPeriodsScreen> {
  List<HiddenPeriod>? _periods;
  bool _busy = false;

  HiddenPeriodsService get _service => ref.read(hiddenPeriodsServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final periods = await _service.mine();
      if (mounted) setState(() => _periods = periods);
    } catch (_) {
      if (mounted) setState(() => _periods = const []);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't change it. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final range = await widget.pickRange(context);
    if (range == null || !mounted) return;
    await _run(() => _service.add(range.start, range.end));
  }

  String _label(HiddenPeriod p) =>
      '${MyDateFormat.toDateShort(p.startsOn)} to ${MyDateFormat.toDateShort(p.endsOn)}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final periods = _periods;
    return Scaffold(
      appBar: AppBar(title: const Text('Hide a period')),
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg.w),
        children: [
          Text(
            "Dates you hide never come back on On this day or as memory "
            'prompts, for you only. Your moments stay where they are.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Gap(Spacing.lg.h),
          if (periods == null)
            const Center(child: CircularProgressIndicator())
          else
            for (final p in periods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(_label(p)),
                trailing: IconButton(
                  tooltip: 'Show again',
                  icon: const Icon(Icons.close),
                  onPressed:
                      _busy ? null : () => _run(() => _service.remove(p.id)),
                ),
              ),
          Gap(Spacing.md.h),
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Add a period'),
          ),
        ],
      ),
    );
  }
}
