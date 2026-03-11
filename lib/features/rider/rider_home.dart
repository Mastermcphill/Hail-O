import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/rideshare/models/ride_search_draft.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/hailo_top_nav.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/ride_search_card.dart';
import '../../widgets/ride_type_card.dart';
import '../../widgets/trust_badge.dart';

class RiderHome extends StatelessWidget {
  const RiderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        HailoSpacing.lg,
        HailoSpacing.md,
        HailoSpacing.lg,
        HailoSpacing.xl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              HailoTopNav(
                title: 'Hail-O Rideshare',
                subtitle: 'Book protected rides in minutes',
                leadingIcon: Icons.person_outline_rounded,
                onLeadingPressed: () => context.go('/rider/profile'),
                onTrailingPressed: () => context.go('/rider/trips'),
              ),
              const SizedBox(height: HailoSpacing.section),
              Wrap(
                spacing: HailoSpacing.lg,
                runSpacing: HailoSpacing.lg,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const PremiumPill(
                          label: 'Passenger home',
                          icon: Icons.local_taxi_outlined,
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Text(
                          'Book city, inter-city, inter-state, and cross-border rides with premium seat choice.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        Text(
                          'Choose your seat tier, compare matches, and travel with escrow payment protection and clear trip progress.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Wrap(
                          spacing: HailoSpacing.xs,
                          runSpacing: HailoSpacing.xs,
                          children: const <Widget>[
                            TrustBadge(
                              label: 'Escrow payment protection',
                              icon: Icons.lock_clock_outlined,
                            ),
                            TrustBadge(
                              label: 'Verified drivers',
                              icon: Icons.verified_user_outlined,
                            ),
                            TrustBadge(
                              label: 'Trip tracking',
                              icon: Icons.timeline_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: RideSearchCard(
                      caption: 'Book a ride now',
                      primaryLabel: 'Search live rides',
                      showCharterMode: true,
                      onSubmit: (draft) => _openRequest(context, draft),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HailoSpacing.section),
              const PremiumSectionHeader(
                eyebrow: 'Ride types',
                title: 'Start with the journey you need.',
                description:
                    'Tap any travel mode to enter live search with the right trip preset already applied.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              Wrap(
                spacing: HailoSpacing.md,
                runSpacing: HailoSpacing.md,
                children: <Widget>[
                  SizedBox(
                    width: 264,
                    child: RideTypeCard(
                      title: 'City rides',
                      description:
                          'Immediate urban trips with quick arrival and clear pricing.',
                      icon: Icons.location_city_outlined,
                      selected: false,
                      onTap: () => _openRequest(
                        context,
                        RideSearchDraft.initial().copyWith(
                          travelMode: RideTravelMode.city,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: RideTypeCard(
                      title: 'Inter-city rides',
                      description:
                          'Smooth premium transfers between nearby city corridors.',
                      icon: Icons.alt_route_rounded,
                      selected: false,
                      onTap: () => _openRequest(
                        context,
                        RideSearchDraft.initial().copyWith(
                          travelMode: RideTravelMode.interCity,
                          seatTier: RideSeatTier.comfort,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: RideTypeCard(
                      title: 'Inter-state rides',
                      description:
                          'Long-distance road travel with better timing and seat choice.',
                      icon: Icons.route_rounded,
                      selected: false,
                      onTap: () => _openRequest(
                        context,
                        RideSearchDraft.initial().copyWith(
                          travelMode: RideTravelMode.interState,
                          seatTier: RideSeatTier.premium,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: RideTypeCard(
                      title: 'Cross-border rides',
                      description:
                          'Trusted border corridors with elevated support and readiness.',
                      icon: Icons.public_rounded,
                      selected: false,
                      onTap: () => _openRequest(
                        context,
                        RideSearchDraft.initial().copyWith(
                          travelMode: RideTravelMode.crossBorder,
                          seatTier: RideSeatTier.executive,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HailoSpacing.section),
              const PremiumSectionHeader(
                eyebrow: 'Quick actions',
                title: 'Everything important is one tap away.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              Wrap(
                spacing: HailoSpacing.md,
                runSpacing: HailoSpacing.md,
                children: <Widget>[
                  SizedBox(
                    width: 264,
                    child: PremiumActionCard(
                      title: 'Recent destinations',
                      description:
                          'Keep your last few pickup and destination pairs close.',
                      icon: Icons.history_rounded,
                      trailingLabel: 'Trips',
                      onTap: () => context.go('/rider/trips'),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: PremiumActionCard(
                      title: 'Saved places',
                      description:
                          'Use Home, Work, and airport favorites for faster booking.',
                      icon: Icons.bookmarks_outlined,
                      trailingLabel: 'Map',
                      onTap: () => context.go('/rider/map'),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: PremiumActionCard(
                      title: 'Trip history',
                      description:
                          'Open timelines, receipts, and trip progress from one place.',
                      icon: Icons.receipt_long_outlined,
                      trailingLabel: 'Open',
                      onTap: () => context.go('/rider/trips'),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: PremiumActionCard(
                      title: 'Become a driver',
                      description:
                          'Apply for the driver network without leaving the premium flow.',
                      icon: Icons.directions_car_outlined,
                      trailingLabel: 'Apply',
                      onTap: () => context.go('/apply/driver'),
                    ),
                  ),
                  SizedBox(
                    width: 264,
                    child: PremiumActionCard(
                      title: 'Register fleet',
                      description:
                          'Launch a fleet operator workspace for your vehicles and drivers.',
                      icon: Icons.directions_bus_outlined,
                      trailingLabel: 'Register',
                      onTap: () => context.go('/apply/fleet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRequest(BuildContext context, RideSearchDraft draft) {
    context.go(
      '/rider/request?draft=${Uri.encodeQueryComponent(draft.toEncoded())}&autosearch=1',
    );
  }
}

class RiderTripsScreen extends StatelessWidget {
  const RiderTripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PremiumSectionHeader(
                eyebrow: 'Trips',
                title: 'Upcoming rides and completed journeys.',
                description:
                    'A cleaner trip hub for timelines, receipts, support, and active ride follow-up.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              PremiumPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    PremiumPill(
                      label: 'Upcoming',
                      icon: Icons.schedule_rounded,
                    ),
                    SizedBox(height: HailoSpacing.md),
                    Text(
                      'Your active timelines and receipts will appear here.',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: HailoSpacing.sm),
                    Text(
                      'Search results, seat confirmation, and trip tracking already connect into this area. Historical records stay intentionally empty until real booking data exists.',
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PremiumSectionHeader(
                eyebrow: 'Safety and support',
                title: 'Stay protected before, during, and after every ride.',
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
                      value: 'Managed in profile',
                      footnote: 'Next-of-kin details stay one tap away.',
                      icon: Icons.health_and_safety_outlined,
                      tint: context.hailoTokens.success,
                    ),
                  ),
                  const SizedBox(
                    width: 300,
                    child: PremiumMetricTile(
                      label: 'Protected payment',
                      value: 'Escrow protected',
                      footnote:
                          'Booking funds are protected until the trip begins.',
                      icon: Icons.lock_clock_outlined,
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: PremiumMetricTile(
                      label: 'Support posture',
                      value: 'Always visible',
                      footnote:
                          'Help and travel readiness stay close to the booking flow.',
                      icon: Icons.support_agent_rounded,
                      tint: context.hailoTokens.warning,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PremiumSectionHeader(
                eyebrow: 'Profile',
                title: 'Account, travel readiness, and support shortcuts.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              PremiumPanel(
                child: Column(
                  children: <Widget>[
                    PremiumActionCard(
                      title: 'Next of kin',
                      description: 'Keep emergency contact details up to date.',
                      icon: Icons.family_restroom_outlined,
                      trailingLabel: 'Manage',
                      onTap: () => context.go('/rider/next-of-kin'),
                    ),
                    const SizedBox(height: HailoSpacing.md),
                    PremiumActionCard(
                      title: 'Travel documents',
                      description:
                          'Keep cross-border and account documents ready.',
                      icon: Icons.description_outlined,
                      trailingLabel: 'Open',
                      onTap: () => context.go('/rider/documents'),
                    ),
                    const SizedBox(height: HailoSpacing.md),
                    PremiumActionCard(
                      title: 'Safety and support',
                      description:
                          'Open travel protection details and support posture.',
                      icon: Icons.shield_outlined,
                      trailingLabel: 'View',
                      onTap: () => context.go('/rider/safety'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
