// Development only: every glass piece over a busy background, so the
// bending, the rim and the animations can be judged on a real device.
//   flutter run -t lib/core/ui/glass/preview/glass_preview_main.dart
// Long-press the title capsule to switch light / dark; tap it to show the
// shader's coordinates (a development check).
import 'package:attune/core/ui/glass/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

/// Development only: run the animations by themselves, slowed down, so
/// screenshots can catch them mid-move.
const bool _autoDemo = false;

class GlassGallery extends StatefulWidget {
  const GlassGallery({super.key, this.onToggleTheme});

  final VoidCallback? onToggleTheme;

  @override
  State<GlassGallery> createState() => _GlassGalleryState();
}

class _GlassGalleryState extends State<GlassGallery> {
  int _tab = 1;
  final _tabKeys = List.generate(3, (i) => GlobalKey());
  String _last = 'Nothing chosen yet';
  final _plusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_autoDemo) {
      timeDilation = 12;
      Future<void>.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _tab = 0);
      });
      Future<void>.delayed(const Duration(seconds: 24), () {
        if (!mounted) return;
        final box = _plusKey.currentContext!.findRenderObject() as RenderBox;
        showGlassMenu<String>(
          context: context,
          anchorRect: box.localToGlobal(Offset.zero) & box.size,
          items: const [
            GlassMenuItem(value: 'voice', label: 'Voice memo', icon: Icons.mic_none),
            GlassMenuItem(value: 'camera', label: 'Open camera', icon: Icons.photo_camera_outlined),
            GlassMenuItem(value: 'photos', label: 'Photo library', icon: Icons.photo_library_outlined),
            GlassMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline, destructive: true),
          ],
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const tabs = [
      (Icons.forum_outlined, 'Opinions'),
      (Icons.chat_bubble_outline, 'Chat'),
      (Icons.event_note_outlined, 'Plans'),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BusyBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  // A floating chat header, WhatsApp-style.
                  Row(
                    children: [
                      GlassCapsuleButton(label: '67', icon: Icons.chevron_left, onPressed: () {}),
                      const SizedBox(width: 10),
                      const CircleAvatar(radius: 20, child: Text('M')),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Magma', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                      LiquidGlass(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined), tooltip: 'Video call'),
                            IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined), tooltip: 'Call'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => LiquidGlassShader.debugCoordinates = !LiquidGlassShader.debugCoordinates,
                      ),
                      onLongPress: widget.onToggleTheme,
                      child: const LiquidGlass(
                        padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        child: Text('Liquid Glass', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassMenuButton<String>(
                        key: _plusKey,
                        tooltip: 'Add',
                        itemBuilder: (_) => const [
                          GlassMenuItem(value: 'voice', label: 'Voice memo', icon: Icons.mic_none),
                          GlassMenuItem(value: 'camera', label: 'Open camera', icon: Icons.photo_camera_outlined),
                          GlassMenuItem(value: 'photos', label: 'Photo library', icon: Icons.photo_library_outlined),
                          GlassMenuItem(value: 'draw', label: 'Draw', icon: Icons.gesture),
                          GlassMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline, destructive: true),
                        ],
                        onSelected: (v) => setState(() => _last = 'Chose $v'),
                        child: const IgnorePointer(
                          child: GlassIconButton(icon: Icons.add, onPressed: _noop, tooltip: 'Add'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlassIconButton(icon: Icons.text_fields, onPressed: () {}, tooltip: 'Text style'),
                      const Spacer(),
                      GlassCapsuleButton(label: 'Go deeper', onPressed: () {}),
                      const SizedBox(width: 12),
                      GlassPrimaryCircle(icon: Icons.chevron_right, onPressed: () {}, tooltip: 'Next'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(child: Text(_last, style: TextStyle(color: scheme.onSurfaceVariant))),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GlassMenuButton<String>(
                      tooltip: 'More',
                      itemBuilder: (_) => const [
                        GlassMenuItem(value: 'select', label: 'Select chats', icon: Icons.check_circle_outline),
                        GlassMenuItem(value: 'read', label: 'Read all', icon: Icons.mark_chat_read_outlined),
                        GlassMenuItem(value: 'privacy', label: 'Status privacy', icon: Icons.lock_outline),
                      ],
                      onSelected: (v) => setState(() => _last = 'Chose $v'),
                      child: const IgnorePointer(
                        child: GlassIconButton(icon: Icons.more_horiz, onPressed: _noop, tooltip: 'More'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // The tab bar with its liquid lens.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: LiquidGlass(
                      refraction: 16,
                      child: SizedBox(
                        height: 62,
                        child: LiquidLensRow(
                          selectedIndex: _tab,
                          itemKeys: _tabKeys,
                          child: Row(
                            children: [
                              for (var i = 0; i < tabs.length; i++)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() => _tab = i),
                                    child: Center(
                                      child: Column(
                                        key: _tabKeys[i],
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(tabs[i].$1, color: i == _tab ? scheme.primary : scheme.onSurfaceVariant),
                                          const SizedBox(height: 2),
                                          Text(
                                            tabs[i].$2,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w500,
                                              color: i == _tab ? scheme.primary : scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}

/// A grid, colour and text: glass only reads as glass over something.
class _BusyBackground extends StatelessWidget {
  const _BusyBackground();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF101418), Color(0xFF2A1F3D), Color(0xFF0E2A24)]
                  : const [Color(0xFFF3EFE6), Color(0xFFE6E9F5), Color(0xFFF7E8EE)],
            ),
          ),
        ),
        CustomPaint(painter: _GridPainter(dark ? const Color(0x22FFFFFF) : const Color(0x22000000))),
        Positioned(
          left: 40,
          top: 190,
          child: Container(width: 90, height: 90, decoration: const BoxDecoration(color: Color(0xFFFF7A59), shape: BoxShape.circle)),
        ),
        Positioned(
          right: 40,
          top: 300,
          child: Container(width: 120, height: 60, decoration: BoxDecoration(color: const Color(0xFF3DDC97), borderRadius: BorderRadius.circular(16))),
        ),
        Positioned(
          left: 150,
          bottom: 60,
          child: Container(width: 110, height: 50, decoration: BoxDecoration(color: const Color(0xFF4C8DFF), borderRadius: BorderRadius.circular(25))),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: 420,
          child: Text(
            'Glass only reads as glass over something: text, colour, a pattern. '
            'Watch the edges bend what is behind them.',
            style: TextStyle(fontSize: 16, color: dark ? Colors.white70 : Colors.black87),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
