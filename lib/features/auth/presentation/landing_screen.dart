import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/role_routes.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/premium_ui.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: HailoDurations.slow,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 24),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HailoSpacing.lg,
                      HailoSpacing.md,
                      HailoSpacing.lg,
                      HailoSpacing.section,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          children: <Widget>[
                            Wrap(
                              spacing: HailoSpacing.sm,
                              runSpacing: HailoSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.spaceBetween,
                              children: <Widget>[
                                SizedBox(
                                  width: 220,
                                  height: 46,
                                  child: Image.asset(
                                    'assets/brand/logo_lockup.png',
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                          Icons.local_taxi_rounded,
                                          size: 34,
                                          color: colorScheme.primary,
                                        ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.go(loginPath),
                                  child: const Text('Sign in'),
                                ),
                                const SizedBox(width: HailoSpacing.xs),
                                FilledButton(
                                  onPressed: () => context.go(signupPath),
                                  child: const Text('Get started'),
                                ),
                              ],
                            ),
                            const SizedBox(height: HailoSpacing.section),
                            PremiumPanel(
                              gradient: context.hailoTokens.heroGradient,
                              borderColor: Colors.white.withValues(alpha: 0.10),
                              child: Wrap(
                                spacing: HailoSpacing.xl,
                                runSpacing: HailoSpacing.lg,
                                children: <Widget>[
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 600,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        PremiumPill(
                                          label: 'Flagship mobility network',
                                          icon: Icons.auto_awesome_rounded,
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.12),
                                          foregroundColor: Colors.white,
                                        ),
                                        const SizedBox(height: HailoSpacing.lg),
                                        Text(
                                          'A premium road-travel operating system for Africa and beyond.',
                                          style: theme.textTheme.displaySmall
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                height: 0.96,
                                              ),
                                        ),
                                        const SizedBox(height: HailoSpacing.md),
                                        Text(
                                          'HAIL-O unifies within-city rides, inter-city journeys, inter-state routes, and cross-border road travel into one elegant, trusted experience for passengers, drivers, and fleet operators.',
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.88,
                                                ),
                                                height: 1.55,
                                              ),
                                        ),
                                        const SizedBox(
                                          height: HailoSpacing.section,
                                        ),
                                        Wrap(
                                          spacing: HailoSpacing.sm,
                                          runSpacing: HailoSpacing.sm,
                                          children: <Widget>[
                                            FilledButton(
                                              onPressed: () =>
                                                  context.go(signupPath),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor:
                                                    colorScheme.primary,
                                              ),
                                              child: const Text('Get started'),
                                            ),
                                            OutlinedButton(
                                              onPressed: () =>
                                                  context.go(loginPath),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: const Text('Sign in'),
                                            ),
                                            OutlinedButton(
                                              onPressed: () => context.go(
                                                driverApplicationPath,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: const Text(
                                                'Become a driver',
                                              ),
                                            ),
                                            OutlinedButton(
                                              onPressed: () => context.go(
                                                fleetRegistrationPath,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: const Text(
                                                'Register fleet',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 360,
                                    ),
                                    child: const _HeroSignalCard(
                                      eyebrow: 'Coverage',
                                      title:
                                          'From quick city movement to cross-border road operations.',
                                      metrics: <_HeroMetric>[
                                        _HeroMetric(
                                          label: 'Within-city',
                                          value: 'Fast everyday rides',
                                        ),
                                        _HeroMetric(
                                          label: 'Inter-city',
                                          value: 'Planned travel between hubs',
                                        ),
                                        _HeroMetric(
                                          label: 'Inter-state',
                                          value: 'Long-distance road movement',
                                        ),
                                        _HeroMetric(
                                          label: 'Cross-border',
                                          value: 'Trusted road corridors only',
                                        ),
                                      ],
                                    ),
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
              ),
              SliverToBoxAdapter(
                child: _SectionWrap(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const PremiumSectionHeader(
                        eyebrow: 'Travel modes',
                        title:
                            'One system, multiple ways to move with confidence.',
                        description:
                            'Each mode is presented with clear intent so first-time travelers understand what HAIL-O covers immediately.',
                      ),
                      const SizedBox(height: HailoSpacing.lg),
                      Wrap(
                        spacing: HailoSpacing.md,
                        runSpacing: HailoSpacing.md,
                        children: _coverageCards
                            .map(
                              (item) => SizedBox(
                                width: 270,
                                child: PremiumActionCard(
                                  title: item.title,
                                  description: item.description,
                                  icon: item.icon,
                                  trailingLabel: item.trailing,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionWrap(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const PremiumSectionHeader(
                        eyebrow: 'How it works',
                        title: 'A calmer journey from discovery to arrival.',
                        description:
                            'The product flow is designed to feel premium without ever becoming confusing.',
                      ),
                      const SizedBox(height: HailoSpacing.lg),
                      Wrap(
                        spacing: HailoSpacing.md,
                        runSpacing: HailoSpacing.md,
                        children: List<Widget>.generate(_steps.length, (index) {
                          final step = _steps[index];
                          return SizedBox(
                            width: 260,
                            child: PremiumPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  PremiumPill(
                                    label: 'Step ${index + 1}',
                                    icon: Icons.bolt_rounded,
                                  ),
                                  const SizedBox(height: HailoSpacing.md),
                                  Text(
                                    step.title,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: HailoSpacing.sm),
                                  Text(
                                    step.description,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionWrap(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const PremiumSectionHeader(
                        eyebrow: 'Designed for every role',
                        title:
                            'Passenger, driver, and fleet owner experiences that feel purpose-built.',
                        description:
                            'Public users understand their path immediately, while internal admin access stays completely outside the public product.',
                      ),
                      const SizedBox(height: HailoSpacing.lg),
                      Wrap(
                        spacing: HailoSpacing.md,
                        runSpacing: HailoSpacing.md,
                        children: _roleCards
                            .map(
                              (item) => SizedBox(
                                width: 340,
                                child: PremiumPanel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      PremiumPill(
                                        label: item.eyebrow,
                                        icon: item.icon,
                                      ),
                                      const SizedBox(height: HailoSpacing.md),
                                      Text(
                                        item.title,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: HailoSpacing.sm),
                                      Text(
                                        item.description,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: HailoSpacing.lg),
                                      FilledButton.tonal(
                                        onPressed: () => context.go(item.path),
                                        child: Text(item.cta),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionWrap(
                  child: PremiumPanel(
                    child: Wrap(
                      spacing: HailoSpacing.lg,
                      runSpacing: HailoSpacing.lg,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const SizedBox(
                          width: 360,
                          child: PremiumSectionHeader(
                            eyebrow: 'Trust and safety',
                            title:
                                'Transport-grade confidence built into the brand.',
                            description:
                                'The experience foregrounds clarity, operator trust, route confidence, and support instead of making users dig for reassurance.',
                          ),
                        ),
                        ..._trustItems.map(
                          (item) => SizedBox(
                            width: 230,
                            child: PremiumListItem(
                              title: item.title,
                              subtitle: item.description,
                              leadingIcon: item.icon,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HailoSpacing.lg,
                    0,
                    HailoSpacing.lg,
                    HailoSpacing.xxl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: PremiumPanel(
                        gradient: context.hailoTokens.heroGradient,
                        borderColor: Colors.white.withValues(alpha: 0.10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Ready to experience a better road-travel product?',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: HailoSpacing.sm),
                            Text(
                              'Open a passenger account, join as a driver, or register your fleet. HAIL-O keeps the public experience clean, premium, and role-correct from the first tap.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                            const SizedBox(height: HailoSpacing.lg),
                            Wrap(
                              spacing: HailoSpacing.sm,
                              runSpacing: HailoSpacing.sm,
                              children: <Widget>[
                                FilledButton(
                                  onPressed: () => context.go(signupPath),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: colorScheme.primary,
                                  ),
                                  child: const Text('Get started'),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      context.go(driverApplicationPath),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Become a driver'),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      context.go(fleetRegistrationPath),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Register fleet'),
                                ),
                              ],
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
      ),
    );
  }
}

class _SectionWrap extends StatelessWidget {
  const _SectionWrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HailoSpacing.lg,
        0,
        HailoSpacing.lg,
        HailoSpacing.section,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }
}

class _HeroSignalCard extends StatelessWidget {
  const _HeroSignalCard({
    required this.eyebrow,
    required this.title,
    required this.metrics,
  });

  final String eyebrow;
  final String title;
  final List<_HeroMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumPanel(
      borderColor: Colors.white.withValues(alpha: 0.14),
      gradient: LinearGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.08),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PremiumPill(
            label: eyebrow,
            icon: Icons.public_rounded,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: HailoSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HailoSpacing.lg),
          ...metrics.map(
            (metric) => Padding(
              padding: const EdgeInsets.only(bottom: HailoSpacing.sm),
              child: PremiumListItem(
                title: metric.label,
                subtitle: metric.value,
                leadingIcon: Icons.arrow_outward_rounded,
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class _CoverageCardData {
  const _CoverageCardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final String trailing;
}

class _StepData {
  const _StepData({required this.title, required this.description});

  final String title;
  final String description;
}

class _RoleCardData {
  const _RoleCardData({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.cta,
    required this.path,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String cta;
  final String path;
  final IconData icon;
}

class _TrustItemData {
  const _TrustItemData({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

const List<_CoverageCardData> _coverageCards = <_CoverageCardData>[
  _CoverageCardData(
    icon: Icons.location_city_rounded,
    title: 'Within-city',
    description:
        'Fast premium movement for everyday work, errands, meetings, and night returns.',
    trailing: 'Urban mobility',
  ),
  _CoverageCardData(
    icon: Icons.alt_route_rounded,
    title: 'Inter-city',
    description:
        'Structured road travel between city hubs with clearer planning and operator context.',
    trailing: 'Regional travel',
  ),
  _CoverageCardData(
    icon: Icons.map_rounded,
    title: 'Inter-state',
    description:
        'Long-distance journeys with route clarity, stronger trust cues, and calmer booking flow.',
    trailing: 'Statewide reach',
  ),
  _CoverageCardData(
    icon: Icons.public_rounded,
    title: 'Cross-border road travel',
    description:
        'Cross-border transport experience designed specifically for road corridors, not flights or trains.',
    trailing: 'Road-only lanes',
  ),
];

const List<_StepData> _steps = <_StepData>[
  _StepData(
    title: 'Choose the journey',
    description:
        'Select your route, timing, and preferred travel mode with clearer information hierarchy.',
  ),
  _StepData(
    title: 'Match to the right operator',
    description:
        'HAIL-O positions the correct rider, driver, or fleet experience without exposing internal tooling.',
  ),
  _StepData(
    title: 'Track movement with confidence',
    description:
        'Keep support, status, and trust cues close throughout the journey instead of burying them in menus.',
  ),
  _StepData(
    title: 'Operate or travel at premium quality',
    description:
        'Every role gets a dedicated workspace designed for clarity, speed, and reliability.',
  ),
];

const List<_RoleCardData> _roleCards = <_RoleCardData>[
  _RoleCardData(
    eyebrow: 'Passenger',
    title: 'Book and manage road travel beautifully.',
    description:
        'Premium booking, trip visibility, support, and account tools without the prototype feel of generic ride apps.',
    cta: 'Create passenger account',
    path: signupPath,
    icon: Icons.person_outline_rounded,
  ),
  _RoleCardData(
    eyebrow: 'Driver',
    title: 'Operate with a calmer, more capable driver workspace.',
    description:
        'Availability, active jobs, earnings, vehicle readiness, and support live inside a dedicated operator shell.',
    cta: 'Become a driver',
    path: driverApplicationPath,
    icon: Icons.local_taxi_outlined,
  ),
  _RoleCardData(
    eyebrow: 'Fleet owner',
    title: 'Run vehicles and drivers from a true operations dashboard.',
    description:
        'Fleet performance, driver visibility, settlements, and compliance are structured for real transport businesses.',
    cta: 'Register fleet',
    path: fleetRegistrationPath,
    icon: Icons.directions_bus_rounded,
  ),
];

const List<_TrustItemData> _trustItems = <_TrustItemData>[
  _TrustItemData(
    title: 'Verified operator posture',
    description:
        'The experience is built to foreground trusted drivers, vehicles, and structured operations.',
    icon: Icons.verified_user_outlined,
  ),
  _TrustItemData(
    title: 'Calm support access',
    description:
        'Support and safety are surfaced clearly, not hidden behind cluttered menus or prototype cards.',
    icon: Icons.support_agent_rounded,
  ),
  _TrustItemData(
    title: 'Clear role separation',
    description:
        'Passenger, driver, and fleet users see purpose-built interfaces while admin stays fully internal.',
    icon: Icons.account_tree_outlined,
  ),
];
