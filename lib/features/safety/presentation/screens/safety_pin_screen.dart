import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/widgets/pin_keypad.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the current-PIN step is for.
enum _CurrentFor { change, remove, everyOpenOff }

enum _Step { overview, choose, confirm, current }

const _intro =
    'After you use quick exit, Attune asks for this PIN before it opens again. '
    'If you forget it, you can sign out and sign back in with your phone number.';

/// Settings → Safety PIN (Spec 2; research 06 §3 F2 (6)).
class SafetyPinScreen extends ConsumerStatefulWidget {
  const SafetyPinScreen({super.key, this.store});

  final SafetyPinStore? store;

  @override
  ConsumerState<SafetyPinScreen> createState() => _SafetyPinScreenState();
}

class _SafetyPinScreenState extends ConsumerState<SafetyPinScreen> {
  SafetyPinStore get _store => widget.store ?? SafetyPinStore.instance;

  bool? _hasPin;
  bool _everyOpen = false;
  _Step _step = _Step.overview;
  _CurrentFor _currentFor = _CurrentFor.change;
  String _entry = '';
  String _chosen = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final has = await _store.hasPin();
    final every = has && await _store.everyOpen();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _everyOpen = every;
    });
  }

  void _go(_Step step, {_CurrentFor? purpose}) => setState(() {
    _step = step;
    if (purpose != null) _currentFor = purpose;
    _entry = '';
    _error = null;
  });

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _advance(_entry);
    } catch (_) {
      // A keystore that can't be written must not leave the screen stuck
      // (review M-2).
      if (mounted) {
        setState(() {
          _entry = '';
          _error = "Couldn't save. Try again.";
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(String pin) async {
    switch (_step) {
      case _Step.choose:
        if (!isValidPin(pin)) {
          setState(() {
            _error = 'Use 4 to 8 digits.';
            _entry = '';
          });
          return;
        }
        _chosen = pin;
        _go(_Step.confirm);
      case _Step.confirm:
        if (pin != _chosen) {
          setState(() {
            _error = "Those PINs didn't match.";
            _entry = '';
            _step = _Step.choose;
          });
          return;
        }
        await _store.setPin(pin);
        _chosen = '';
        await _load();
        _go(_Step.overview);
      case _Step.current:
        final r = await _store.check(pin);
        if (r.result != PinCheck.ok) {
          setState(() {
            _entry = '';
            _error =
                r.result == PinCheck.waiting
                    ? 'Try again later.'
                    : "That PIN didn't match.";
          });
          return;
        }
        switch (_currentFor) {
          case _CurrentFor.change:
            _go(_Step.choose);
          case _CurrentFor.remove:
            await _store.clearAll();
            await _load();
            _go(_Step.overview);
          case _CurrentFor.everyOpenOff:
            await _store.setEveryOpen(false);
            await _load();
            _go(_Step.overview);
        }
      case _Step.overview:
        break;
    }
  }

  String get _prompt => switch (_step) {
    _Step.choose => 'Choose a 4–8 digit PIN',
    _Step.confirm => 'Enter it again',
    _Step.current => 'Enter your current PIN',
    _Step.overview => '',
  };

  Widget _entryStep(TextTheme text, ColorScheme scheme) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_prompt, style: text.titleMedium, textAlign: TextAlign.center),
            SizedBox(
              height: 32,
              child:
                  _error == null
                      ? null
                      : Center(
                        child: Text(
                          _error!,
                          style: text.bodyMedium?.copyWith(color: scheme.error),
                        ),
                      ),
            ),
            PinKeypad(
              length: _entry.length,
              enabled: !_busy,
              onDigit:
                  (d) => setState(() {
                    if (_entry.length < 8) _entry += d;
                  }),
              onDelete:
                  () => setState(() {
                    if (_entry.isNotEmpty) {
                      _entry = _entry.substring(0, _entry.length - 1);
                    }
                  }),
            ),
            Gap(Spacing.md.h),
            FilledButton(
              onPressed: _entry.length >= 4 && !_busy ? _next : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(TextTheme text, ColorScheme scheme) {
    final hasPin = _hasPin ?? false;
    return ListView(
      padding: EdgeInsets.all(Spacing.lg.w),
      children: [
        Text(
          _intro,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Gap(Spacing.lg.h),
        if (!hasPin)
          FilledButton(
            onPressed: () => _go(_Step.choose),
            child: const Text('Set a PIN'),
          )
        else ...[
          InfoRowWidget(
            title: 'Ask for my PIN every time Attune opens',
            subtitle: '',
            icon: Icons.lock_clock_outlined,
            showAvatar: false,
            showDivider: false,
            isToggleItem: true,
            toggleValue: _everyOpen,
            onToggleChanged: (on) async {
              if (on) {
                await _store.setEveryOpen(true);
                await _load();
              } else {
                // Turning protection down needs the PIN (review I12).
                _go(_Step.current, purpose: _CurrentFor.everyOpenOff);
              }
            },
          ),
          Gap(Spacing.md.h),
          OutlinedButton(
            onPressed: () => _go(_Step.current, purpose: _CurrentFor.change),
            child: const Text('Change PIN'),
          ),
          Gap(Spacing.sm.h),
          TextButton(
            onPressed: () => _go(_Step.current, purpose: _CurrentFor.remove),
            child: const Text('Remove PIN'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety PIN'),
        leading:
            _step == _Step.overview
                ? null
                : BackButton(onPressed: () => _go(_Step.overview)),
      ),
      body:
          _hasPin == null
              ? const SizedBox.shrink()
              : _step == _Step.overview
              ? _overview(text, scheme)
              : _entryStep(text, scheme),
    );
  }
}

/// The one-time "Set a Safety PIN" offer on Support resources (F2 (6)).
class SafetyPinPromptCard extends StatefulWidget {
  const SafetyPinPromptCard({super.key, this.store});

  final SafetyPinStore? store;

  static const dismissedKey = 'safety_pin_prompt_dismissed';

  @override
  State<SafetyPinPromptCard> createState() => _SafetyPinPromptCardState();
}

class _SafetyPinPromptCardState extends State<SafetyPinPromptCard> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = widget.store ?? SafetyPinStore.instance;
    final prefs = await SharedPreferences.getInstance();
    final show =
        !(prefs.getBool(SafetyPinPromptCard.dismissedKey) ?? false) &&
        !await store.hasPin();
    if (mounted) setState(() => _show = show);
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SafetyPinPromptCard.dismissedKey, true);
    if (mounted) setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.md.h),
      child: CardInkWell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set a Safety PIN', style: text.titleSmall),
            Gap(Spacing.xs.h),
            Text(
              'So no one can open Attune after you leave it in a hurry.',
              style: text.bodyMedium,
            ),
            Gap(Spacing.sm.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _dismiss, child: const Text('Not now')),
                Gap(Spacing.sm.w),
                FilledButton(
                  onPressed: () => context.pushNamed('safetyPin'),
                  child: const Text('Set PIN'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
