// lib/features/pulse/presentation/screens/pulse_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pulse_screen.dart';

class PulseTab extends ConsumerStatefulWidget {
  const PulseTab({super.key});

  @override
  ConsumerState<PulseTab> createState() => _PulseTabState();
}

class _PulseTabState extends ConsumerState<PulseTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // Pill switcher
          Container(
            margin: EdgeInsets.only(top: Spacing.md.h),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.xl.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPillOption('Pulse', 0),
                    _buildPillOption('Timeline', 1),
                  ],
                ),
              ),
            ),
          ),
          // Tab bar view
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const PageScrollPhysics(),
              children: const [PulseScreen(), TimelineScreen()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOption(String label, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _tabController.index == index;

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.lg.w,
          vertical: Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.xl.r),
        ),
        child: Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color:
                isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
