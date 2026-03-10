import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/premium_ui.dart';

class RiderHome extends StatelessWidget {
  const RiderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PremiumPanel(
              gradient: context.hailoTokens.heroGradient,
              borderColor: Colors.white.withValues(alpha: 0.10),
              child: Wrap(
                spacing: HailoSpacing.xl,
                runSpacing: HailoSpacing.lg,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const PremiumPill(
                          label: 'Passenger workspace',
                          icon: Icons.route_rounded,
                          backgroundColor: Color(0x29FFFFFF),
                          foregroundColor: Colors.white,
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Text(
                          'Travel with a calmer, clearer booking experience.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        Text(
                          'Request rides, plan journeys, track travel, and keep safety close without wading through prototype menus.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Wrap(
                          spacing: HailoSpacing.sm,
                          runSpacing: HailoSpacing.sm,
                          children: <Widget>[
                            FilledButton(
                              onPressed: () => context.go('/rider/request'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                              child: const Text('Request a ride'),
                            ),
                            OutlinedButton(
                              onPressed: () => context.go('/rider/trips'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Text('View trips'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 320, child: _RiderSignalColumn()),
                ],
              ),
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Quick actions',
              title: 'Everything important is one tap away.',
              description:
                  'The primary rider tasks are surfaced clearly instead of buried in raw utility buttons.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Plan a journey',
                    description:
                        'Open the ride request flow for city, regional, or long-distance road travel.',
                    icon: Icons.map_outlined,
                    trailingLabel: 'Book now',
                    onTap: () => context.go('/rider/request'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Support and safety',
                    description:
                        'Keep emergency contacts, travel safeguards, and support channels close.',
                    icon: Icons.shield_outlined,
                    trailingLabel: 'Stay covered',
                    onTap: () => context.go('/rider/safety'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Account readiness',
                    description:
                        'Manage next of kin, documents, and profile essentials without clutter.',
                    icon: Icons.account_circle_outlined,
                    trailingLabel: 'Profile',
                    onTap: () => context.go('/rider/profile'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Travel rhythm',
              title: 'Upcoming plans and saved essentials.',
              description:
                  'The shell is ready for live trip history and upcoming bookings, with graceful placeholders until more backend data is connected.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: const <Widget>[
                SizedBox(width: 540, child: _UpcomingTripPanel()),
                SizedBox(width: 540, child: _SavedPlacesPanel()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RiderTripsScreen extends StatelessWidget {
  const RiderTripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PremiumSectionHeader(
              eyebrow: 'Trips',
              title: 'Upcoming journeys and recent movement.',
              description:
                  'This space is structured for live trip history, upcoming departures, and active ride status without overwhelming new users.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            PremiumPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const PremiumPill(
                    label: 'Next departure',
                    icon: Icons.schedule_rounded,
                  ),
                  const SizedBox(height: HailoSpacing.md),
                  Text(
                    'Abuja to Kaduna Road Corridor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: HailoSpacing.xs),
                  Text(
                    'Friday, 07:30 AM | Premium coach seat | Operator assigned',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HailoSpacing.lg),
                  FilledButton.tonal(
                    onPressed: null,
                    child: const Text('Live trip feed connects here'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HailoSpacing.lg),
            PremiumPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  PremiumSectionHeader(
                    eyebrow: 'Recent activity',
                    title: 'Your history will appear here cleanly.',
                    description:
                        'Trip history UI is ready for backend data. For now the experience avoids fake records and keeps the empty state intentional.',
                  ),
                  SizedBox(height: HailoSpacing.lg),
                  EmptyState(
                    title: 'No completed trips yet',
                    message:
                        'Once you complete journeys, your road-travel history and receipts will appear here.',
                    actionLabel: 'Request a ride',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RiderSafetyScreen extends StatelessWidget {
  const RiderSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PremiumSectionHeader(
              eyebrow: 'Safety and support',
              title: 'Built to reassure before, during, and after every trip.',
              description:
                  'Support tools, emergency contacts, and trust cues stay visible so riders never feel stranded inside the product.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'Emergency readiness',
                    value: 'Configured',
                    footnote: 'Next-of-kin flow stays one tap away.',
                    icon: Icons.health_and_safety_outlined,
                    tint: context.hailoTokens.success,
                  ),
                ),
                const SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'Operator verification',
                    value: 'Clear trust cues',
                    footnote:
                        'Vehicles and operators are designed to feel verifiable.',
                    icon: Icons.verified_user_outlined,
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'Support posture',
                    value: 'Always close',
                    footnote:
                        'Escalation and support surfaces stay visible in the shell.',
                    icon: Icons.support_agent_rounded,
                    tint: context.hailoTokens.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HailoSpacing.lg),
            PremiumPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const PremiumSectionHeader(
                    eyebrow: 'Safety shortcuts',
                    title: 'Keep personal protections current.',
                  ),
                  const SizedBox(height: HailoSpacing.lg),
                  PremiumActionCard(
                    title: 'Manage next of kin',
                    description:
                        'Review or update the emergency contact attached to your account.',
                    icon: Icons.family_restroom_outlined,
                    trailingLabel: 'Update',
                    onTap: () => context.go('/rider/next-of-kin'),
                  ),
                  const SizedBox(height: HailoSpacing.md),
                  PremiumActionCard(
                    title: 'Review travel documents',
                    description:
                        'Keep account documentation and travel readiness in one place.',
                    icon: Icons.description_outlined,
                    trailingLabel: 'Open',
                    onTap: () => context.go('/rider/documents'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RiderProfileScreen extends StatelessWidget {
  const RiderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PremiumSectionHeader(
              eyebrow: 'Profile',
              title: 'Your account, documents, and travel preferences.',
              description:
                  'This profile shell is designed for clarity first, with room for richer identity and preference data as integrations deepen.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 460,
                  child: PremiumPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        PremiumPill(
                          label: 'Account center',
                          icon: Icons.person_outline_rounded,
                        ),
                        SizedBox(height: HailoSpacing.md),
                        PremiumListItem(
                          title: 'Passenger profile',
                          subtitle:
                              'Identity details, preferences, and payment tools expand here over time.',
                          leadingIcon: Icons.account_circle_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 460,
                  child: PremiumPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const PremiumPill(
                          label: 'Readiness',
                          icon: Icons.inventory_2_outlined,
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        PremiumActionCard(
                          title: 'Travel documents',
                          description:
                              'Keep your rider documentation reviewed and accessible.',
                          icon: Icons.badge_outlined,
                          trailingLabel: 'Manage',
                          onTap: () => context.go('/rider/documents'),
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        PremiumActionCard(
                          title: 'Emergency contact',
                          description:
                              'Review the next of kin attached to your account.',
                          icon: Icons.call_outlined,
                          trailingLabel: 'Review',
                          onTap: () => context.go('/rider/next-of-kin'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderSignalColumn extends StatelessWidget {
  const _RiderSignalColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const <Widget>[
        PremiumMetricTile(
          label: 'Travel scope',
          value: 'City to cross-border',
          footnote: 'One app for everyday movement and planned road journeys.',
          icon: Icons.public_rounded,
        ),
        SizedBox(height: HailoSpacing.md),
        PremiumMetricTile(
          label: 'Support posture',
          value: 'Safety-first',
          footnote:
              'Support and rider safeguards stay visible across the shell.',
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }
}

class _UpcomingTripPanel extends StatelessWidget {
  const _UpcomingTripPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PremiumSectionHeader(
            eyebrow: 'Upcoming',
            title: 'Your next journey lives here.',
            description:
                'Ready for live route and booking data once the fuller rider history feed is connected.',
          ),
          const SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'No upcoming ride yet',
            subtitle:
                'Book your next within-city or long-distance road trip to populate this panel.',
            leadingIcon: Icons.event_available_outlined,
            trailing: FilledButton.tonal(
              onPressed: () => context.go('/rider/request'),
              child: const Text('Book'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPlacesPanel extends StatelessWidget {
  const _SavedPlacesPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Saved essentials',
            title: 'Home, work, and frequent corridors.',
            description:
                'This premium shell leaves room for saved places and preferred routes without filling the screen with fake records.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Home and work shortcuts',
            subtitle:
                'Saved places appear here once the rider preference store is connected.',
            leadingIcon: Icons.place_outlined,
          ),
        ],
      ),
    );
  }
}
