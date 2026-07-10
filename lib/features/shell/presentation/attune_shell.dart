import 'package:flutter/material.dart';

class AttuneShell extends StatefulWidget {
  const AttuneShell({super.key});

  @override
  State<AttuneShell> createState() => _AttuneShellState();
}

class _AttuneShellState extends State<AttuneShell> {
  int _selectedIndex = 1;

  static const _tabs = <_AttuneTab>[
    _AttuneTab(
      label: 'Pulse',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      screen: _PlaceholderScreen(
        title: 'Pulse',
        subtitle: 'Relationship rhythm, safety signals, and daily check-ins.',
        icon: Icons.monitor_heart,
      ),
    ),
    _AttuneTab(
      label: 'Chat',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      screen: _PlaceholderScreen(
        title: 'Chat',
        subtitle: 'The shared conversation space for partners.',
        icon: Icons.chat_bubble,
      ),
    ),
    _AttuneTab(
      label: 'Games',
      icon: Icons.extension_outlined,
      selectedIcon: Icons.extension,
      screen: _PlaceholderScreen(
        title: 'Games',
        subtitle: 'Prompts and playful exercises for connection.',
        icon: Icons.extension,
      ),
    ),
    _AttuneTab(
      label: 'Insights',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      screen: _PlaceholderScreen(
        title: 'Insights',
        subtitle: 'Patterns, summaries, and monthly relationship readouts.',
        icon: Icons.insights,
      ),
    ),
    _AttuneTab(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      screen: _PlaceholderScreen(
        title: 'Profile',
        subtitle: 'Identity, partner pairing, privacy, and settings.',
        icon: Icons.person,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [for (final tab in _tabs) tab.screen],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _AttuneTab {
  const _AttuneTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            subtitle,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$title placeholder',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
