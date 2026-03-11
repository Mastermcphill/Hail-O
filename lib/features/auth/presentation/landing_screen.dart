import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/role_routes.dart';
import '../../../features/rideshare/models/ride_search_draft.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/hailo_top_nav.dart';
import '../../../widgets/premium_ui.dart';
import '../../../widgets/ride_search_card.dart';
import '../../../widgets/ride_type_card.dart';
import '../../../widgets/trust_badge.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              HailoSpacing.lg,
              HailoSpacing.md,
              HailoSpacing.lg,
              HailoSpacing.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    HailoTopNav(
                      title: 'Hail-O Rideshare',
                      subtitle:
                          'Premium rides across cities, states, and borders',
                      leadingIcon: Icons.person_outline_rounded,
                      onLeadingPressed: () => context.go(loginPath),
                      onTrailingPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Travel alerts and ride updates appear here after sign in.',
                              ),
                            ),
                          ),
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
                                label: 'Escrow-protected booking',
                                icon: Icons.lock_clock_outlined,
                              ),
                              const SizedBox(height: HailoSpacing.lg),
                              Text(
                                'Hail-O Rideshare',
                                style: Theme.of(
                                  context,
                                ).textTheme.displayMedium,
                              ),
                              const SizedBox(height: HailoSpacing.sm),
                              Text(
                                'Premium rides across cities, states, and borders',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: HailoSpacing.md),
                              Text(
                                'Secure booking with escrow payment protection, premium seat tiers, verified operators, and clear booking flow from search to arrival.',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: HailoSpacing.lg),
                              Wrap(
                                spacing: HailoSpacing.sm,
                                runSpacing: HailoSpacing.sm,
                                children: <Widget>[
                                  FilledButton(
                                    onPressed: () => context.go(signupPath),
                                    child: const Text('Get started'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => context.go(loginPath),
                                    child: const Text('Sign in'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () =>
                                        context.go(driverApplicationPath),
                                    child: const Text('Become a driver'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () =>
                                        context.go(fleetRegistrationPath),
                                    child: const Text('Register fleet'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: HailoSpacing.lg),
                              Wrap(
                                spacing: HailoSpacing.xs,
                                runSpacing: HailoSpacing.xs,
                                children: const <Widget>[
                                  TrustBadge(
                                    label: 'Escrow payment protection',
                                    icon: Icons.shield_outlined,
                                  ),
                                  TrustBadge(
                                    label: 'Verified drivers',
                                    icon: Icons.verified_user_outlined,
                                  ),
                                  TrustBadge(
                                    label: 'Live trip tracking',
                                    icon: Icons.gps_fixed_rounded,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 580),
                          child: RideSearchCard(
                            caption: 'Book a ride',
                            primaryLabel: 'Search rides',
                            onSubmit: (draft) => _openPreview(context, draft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HailoSpacing.section),
                    const PremiumSectionHeader(
                      eyebrow: 'Travel modes',
                      title: 'Choose the network that fits this journey.',
                      description:
                          'Action first. Pick a route type, then refine seats and schedule in the booking flow.',
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
                                'Fast urban bookings for airport runs, work trips, and everyday movement.',
                            icon: Icons.location_city_outlined,
                            selected: false,
                            onTap: () => _openPreview(
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
                                'Smooth premium transfers between neighboring hubs with seat selection.',
                            icon: Icons.alt_route_rounded,
                            selected: false,
                            onTap: () => _openPreview(
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
                                'Long-distance road travel with premium comfort and clearer timing.',
                            icon: Icons.directions_rounded,
                            selected: false,
                            onTap: () => _openPreview(
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
                                'Trusted corridor travel with stronger border-readiness and premium trust framing.',
                            icon: Icons.public_rounded,
                            selected: false,
                            onTap: () => _openPreview(
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
                      eyebrow: 'Why riders trust Hail-O',
                      title:
                          'Money protection, safer operators, and clearer booking.',
                    ),
                    const SizedBox(height: HailoSpacing.lg),
                    Wrap(
                      spacing: HailoSpacing.md,
                      runSpacing: HailoSpacing.md,
                      children: const <Widget>[
                        SizedBox(
                          width: 360,
                          child: PremiumMetricTile(
                            label: 'Escrow protection',
                            value: 'Funds held securely',
                            footnote:
                                'Your payment is held securely until the journey begins.',
                            icon: Icons.lock_clock_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: PremiumMetricTile(
                            label: 'Seat intelligence',
                            value: 'Standard to Executive',
                            footnote:
                                'Choose your tier before booking and refine your seat after match.',
                            icon: Icons.event_seat_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: PremiumMetricTile(
                            label: 'Network reach',
                            value: 'City to cross-border',
                            footnote:
                                'One product for urban rides, regional trips, and long-distance road travel.',
                            icon: Icons.public_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HailoSpacing.section),
                    const PremiumSectionHeader(
                      eyebrow: 'Quick actions',
                      title: 'Move directly to the next step.',
                    ),
                    const SizedBox(height: HailoSpacing.lg),
                    Wrap(
                      spacing: HailoSpacing.md,
                      runSpacing: HailoSpacing.md,
                      children: <Widget>[
                        SizedBox(
                          width: 260,
                          child: PremiumActionCard(
                            title: 'Recent destinations',
                            description:
                                'Sign in to reuse saved routes and faster booking.',
                            icon: Icons.history_toggle_off_rounded,
                            trailingLabel: 'Sign in',
                            onTap: () => context.go(loginPath),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: PremiumActionCard(
                            title: 'Saved places',
                            description:
                                'Keep home, work, and airport routes one tap away.',
                            icon: Icons.bookmark_outline_rounded,
                            trailingLabel: 'Account',
                            onTap: () => context.go(signupPath),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: PremiumActionCard(
                            title: 'Trip history',
                            description:
                                'View receipts and trip progression after your first booking.',
                            icon: Icons.receipt_long_outlined,
                            trailingLabel: 'Open',
                            onTap: () => context.go(loginPath),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: PremiumActionCard(
                            title: 'Become a driver',
                            description:
                                'Apply for the premium operator network with a driver-first workspace.',
                            icon: Icons.directions_car_filled_outlined,
                            trailingLabel: 'Apply',
                            onTap: () => context.go(driverApplicationPath),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: PremiumActionCard(
                            title: 'Register fleet',
                            description:
                                'Launch a fleet operator workspace for vehicles, drivers, and routes.',
                            icon: Icons.directions_bus_outlined,
                            trailingLabel: 'Register',
                            onTap: () => context.go(fleetRegistrationPath),
                          ),
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
    );
  }

  void _openPreview(BuildContext context, RideSearchDraft draft) {
    context.go(
      '$previewResultsPath?draft=${Uri.encodeQueryComponent(draft.toEncoded())}',
    );
  }
}
