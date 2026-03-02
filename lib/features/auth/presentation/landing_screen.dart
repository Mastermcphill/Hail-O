import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          height: 58,
                          child: Image.asset(
                            'assets/brand/logo_lockup.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.local_taxi,
                              size: 44,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                'HAIL-O Road Travel',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Book rides and seats for within-city trips, inter-city journeys, inter-state routes, and cross-border road travel using cars, buses, and coaches.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Cross-border is road travel only (no flights, no trains).',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  FilledButton(
                                    onPressed: () => context.go('/signup'),
                                    child: const Text('Get Started'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => context.go('/login'),
                                    child: const Text('Sign in'),
                                  ),
                                  TextButton(
                                    onPressed: () => context.go('/admin-login'),
                                    child: const Text('Admin login'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _FeatureCard(item: _featureCards[index]),
                    ),
                  );
                }, childCount: _featureCards.length),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent: 236,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                title: 'How It Works',
                child: Column(
                  children: List<Widget>.generate(
                    _steps.length,
                    (index) =>
                        _StepTile(number: index + 1, label: _steps[index]),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                title: 'Travel With Confidence',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _trustItems
                      .map((item) => Chip(label: Text(item)))
                      .toList(growable: false),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Ready to hit the road?',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => context.go('/signup'),
                            child: const Text('Get Started'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCardData {
  const _FeatureCardData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});

  final _FeatureCardData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(item.icon, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text(item.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              item.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.28,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.label});

  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: Text('$number'),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

const List<_FeatureCardData> _featureCards = <_FeatureCardData>[
  _FeatureCardData(
    icon: Icons.location_city_outlined,
    title: 'Within City',
    body: 'Quick rides and shared trips across town.',
  ),
  _FeatureCardData(
    icon: Icons.route_outlined,
    title: 'Inter City',
    body: 'Cars, buses, and coaches between cities.',
  ),
  _FeatureCardData(
    icon: Icons.map_outlined,
    title: 'Inter State',
    body: 'Long-distance routes across states.',
  ),
  _FeatureCardData(
    icon: Icons.public_outlined,
    title: 'Inter Country (Cross-Border)',
    body:
        'Cross-border road travel by car, bus, or coach. No flights. No trains.',
  ),
];

const List<String> _steps = <String>[
  'Choose route (pickup, destination, date)',
  'Pick vehicle (car, bus, coach)',
  'Track trip',
  'Arrive safely',
];

const List<String> _trustItems = <String>[
  'Verified drivers and vehicles',
  'Clear pricing before booking',
  'Trip tracking and support',
];
