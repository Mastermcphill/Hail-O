import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/routing/role_routes.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/hailo_top_nav.dart';
import '../../../widgets/premium_ui.dart';
import '../../../widgets/ride_result_card.dart';
import '../../../widgets/trust_badge.dart';
import '../models/ride_search_draft.dart';

class PublicRidePreviewScreen extends StatelessWidget {
  const PublicRidePreviewScreen({super.key, required this.draftEncoded});

  final String? draftEncoded;

  @override
  Widget build(BuildContext context) {
    final draft = RideSearchDraft.fromEncoded(draftEncoded);
    final previewOptions = _buildPreviewOptions(draft);

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
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    HailoTopNav(
                      title: 'Hail-O Rideshare',
                      subtitle: 'Preview ride matches before sign in',
                      showBack: true,
                      onBack: () => context.go(landingPath),
                      onTrailingPressed: () => context.go(loginPath),
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
                            constraints: const BoxConstraints(maxWidth: 580),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const PremiumPill(
                                  label: 'Ride preview',
                                  icon: Icons.visibility_outlined,
                                  backgroundColor: Color(0x24FFFFFF),
                                  foregroundColor: Colors.white,
                                ),
                                const SizedBox(height: HailoSpacing.lg),
                                Text(
                                  '${draft.travelModeLabel} from ${draft.pickup.isEmpty ? 'your location' : draft.pickup} to ${draft.destination.isEmpty ? 'your destination' : draft.destination}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: HailoSpacing.md),
                                Text(
                                  'Choose ${draft.seatTierLabel.toLowerCase()} comfort, see likely matches, and sign in only when you are ready to book with escrow protection.',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _SummaryLine(
                                  label: 'Departure',
                                  value: DateFormat(
                                    'EEE, MMM d • h:mm a',
                                  ).format(draft.departureAt.toLocal()),
                                ),
                                const SizedBox(height: HailoSpacing.sm),
                                _SummaryLine(
                                  label: 'Passengers',
                                  value: '${draft.passengerCount}',
                                ),
                                const SizedBox(height: HailoSpacing.sm),
                                _SummaryLine(
                                  label: 'Seat tier',
                                  value: draft.seatTierLabel,
                                ),
                                const SizedBox(height: HailoSpacing.lg),
                                Wrap(
                                  spacing: HailoSpacing.xs,
                                  runSpacing: HailoSpacing.xs,
                                  children: const <Widget>[
                                    TrustBadge(
                                      label: 'Escrow protection',
                                      icon: Icons.lock_outline_rounded,
                                      tint: Colors.white,
                                    ),
                                    TrustBadge(
                                      label: 'Verified operators',
                                      icon: Icons.verified_user_outlined,
                                      tint: Colors.white,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HailoSpacing.section),
                    const PremiumSectionHeader(
                      eyebrow: 'Preview results',
                      title: 'Likely matches for this journey',
                      description:
                          'These are curated previews. Sign in as a passenger to request live offers, unlock seats, and complete protected booking.',
                    ),
                    const SizedBox(height: HailoSpacing.lg),
                    for (final option in previewOptions) ...<Widget>[
                      RideResultCard(
                        category: option.category,
                        operatorName: option.operatorName,
                        scheduleLabel: option.scheduleLabel,
                        priceLabel: option.priceLabel,
                        ratingLabel: option.ratingLabel,
                        seatAvailabilityLabel: option.seatAvailabilityLabel,
                        heroNote: option.heroNote,
                        tags: option.tags,
                        trustBadges: option.trustBadges,
                        primaryLabel: 'Continue to book',
                        secondaryLabel: 'Sign in',
                        onPrimaryPressed: () =>
                            _continueToLogin(context, draft),
                        onSecondaryPressed: () =>
                            _continueToLogin(context, draft),
                      ),
                      const SizedBox(height: HailoSpacing.md),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _continueToLogin(BuildContext context, RideSearchDraft draft) {
    final target =
        '/rider/request?draft=${Uri.encodeQueryComponent(draft.toEncoded())}&autosearch=1';
    context.go('$loginPath?next=${Uri.encodeQueryComponent(target)}');
  }
}

class _PreviewOption {
  const _PreviewOption({
    required this.category,
    required this.operatorName,
    required this.scheduleLabel,
    required this.priceLabel,
    required this.ratingLabel,
    required this.seatAvailabilityLabel,
    required this.tags,
    required this.heroNote,
    required this.trustBadges,
  });

  final String category;
  final String operatorName;
  final String scheduleLabel;
  final String priceLabel;
  final String ratingLabel;
  final String seatAvailabilityLabel;
  final List<String> tags;
  final String heroNote;
  final List<TrustBadge> trustBadges;
}

List<_PreviewOption> _buildPreviewOptions(RideSearchDraft draft) {
  final departure = draft.departureAt.toLocal();
  final basePrice = draft.baseFareMinor + draft.premiumMarkupMinor;
  return <_PreviewOption>[
    _PreviewOption(
      category: '${draft.seatTierLabel} Ride',
      operatorName: 'Hail-O Priority Network',
      scheduleLabel: DateFormat('h:mm a').format(departure),
      priceLabel: _money(basePrice),
      ratingLabel: '4.9',
      seatAvailabilityLabel: '4 seats left',
      tags: const <String>['Fastest', 'Escrow protected'],
      heroNote:
          'Direct route with the shortest transfer window and premium support.',
      trustBadges: const <TrustBadge>[
        TrustBadge(label: 'Escrow held', icon: Icons.lock_clock_outlined),
        TrustBadge(label: 'Live tracking', icon: Icons.gps_fixed_rounded),
      ],
    ),
    _PreviewOption(
      category: draft.travelMode == RideTravelMode.city
          ? 'Comfort Ride'
          : 'Shared ${draft.travelModeLabel}',
      operatorName: 'Verified mobility operator',
      scheduleLabel: DateFormat(
        'h:mm a',
      ).format(departure.add(const Duration(minutes: 18))),
      priceLabel: _money((basePrice * 0.88).round()),
      ratingLabel: '4.8',
      seatAvailabilityLabel: '6 seats left',
      tags: const <String>['Most affordable', 'Shared route'],
      heroNote:
          'The best value option for flexible departures and lower total fare.',
      trustBadges: const <TrustBadge>[
        TrustBadge(label: 'Verified driver', icon: Icons.verified_outlined),
        TrustBadge(label: 'Seat choice', icon: Icons.event_seat_outlined),
      ],
    ),
    _PreviewOption(
      category: draft.travelMode == RideTravelMode.crossBorder
          ? 'Cross-border Executive'
          : 'Executive Ride',
      operatorName: 'Premium fleet operator',
      scheduleLabel: DateFormat(
        'h:mm a',
      ).format(departure.add(const Duration(minutes: 32))),
      priceLabel: _money((basePrice * 1.34).round()),
      ratingLabel: '5.0',
      seatAvailabilityLabel: '2 executive seats',
      tags: const <String>['Premium option', 'Most comfortable'],
      heroNote:
          'Top-tier seating, quieter cabin space, and priority pickup coordination.',
      trustBadges: const <TrustBadge>[
        TrustBadge(label: 'Operator on file', icon: Icons.badge_outlined),
        TrustBadge(label: 'Escrow protected', icon: Icons.security_rounded),
      ],
    ),
  ];
}

String _money(int amountMinor) {
  return '\$${(amountMinor / 100).toStringAsFixed(2)}';
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 98,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
