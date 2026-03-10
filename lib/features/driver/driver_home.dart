import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool _isOnline = true;

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
                        PremiumPill(
                          label: _isOnline
                              ? 'Online and discoverable'
                              : 'Offline',
                          icon: _isOnline
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          backgroundColor: _isOnline
                              ? context.hailoTokens.success.withValues(
                                  alpha: 0.14,
                                )
                              : Colors.white.withValues(alpha: 0.12),
                          foregroundColor: _isOnline
                              ? context.hailoTokens.success
                              : Colors.white,
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Text(
                          'Operate with a premium driver cockpit.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        Text(
                          'Availability, ride flow, earnings, compliance, and support live inside one driver-first workspace.',
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
                              onPressed: () {
                                setState(() {
                                  _isOnline = !_isOnline;
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                              child: Text(
                                _isOnline ? 'Go offline' : 'Go online',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => context.go('/driver/jobs'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Text('Open jobs'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: <Widget>[
                        PremiumMetricTile(
                          label: 'Today',
                          value: 'NGN 148,500',
                          footnote: 'Projected from completed and active work.',
                          icon: Icons.payments_outlined,
                          tint: context.hailoTokens.success,
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        PremiumMetricTile(
                          label: 'Readiness',
                          value: _isOnline ? 'Accepting trips' : 'Standby mode',
                          footnote:
                              'Vehicle, documents, and support readiness stay visible.',
                          icon: Icons.verified_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Quick actions',
              title: 'Move from availability to execution without friction.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Offer on a ride',
                    description:
                        'Enter the offer workspace to price or respond to rider demand.',
                    icon: Icons.local_offer_outlined,
                    trailingLabel: 'Active bids',
                    onTap: () => context.go('/driver/offer'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Open ride operations',
                    description:
                        'Manage pickup, in-trip actions, and ride-state transitions with clearer control.',
                    icon: Icons.directions_car_filled_outlined,
                    trailingLabel: 'Ops',
                    onTap: () => context.go('/driver/ride-ops'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: PremiumActionCard(
                    title: 'Route chain planning',
                    description:
                        'Build or review route chains for stronger dispatch readiness.',
                    icon: Icons.alt_route_rounded,
                    trailingLabel: 'Routes',
                    onTap: () => context.go('/driver/route-chain'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Today at a glance',
              title: 'Performance, assigned work, and support posture.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: const <Widget>[
                SizedBox(width: 540, child: _DriverAssignmentsPanel()),
                SizedBox(width: 540, child: _DriverSupportPanel()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const <Widget>[
            PremiumSectionHeader(
              eyebrow: 'Jobs',
              title: 'Assigned and available trip flow.',
              description:
                  'The shell is ready for live dispatch and offer queues. Until deeper backend feeds are connected, the UX stays clear instead of pretending there are jobs.',
            ),
            SizedBox(height: HailoSpacing.lg),
            _DriverAssignmentsPanel(),
          ],
        ),
      ),
    );
  }
}

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

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
              eyebrow: 'Earnings',
              title: 'A premium summary of today, week, and performance.',
              description:
                  'Designed to scale into live payout and earning feeds while already giving drivers a calm financial overview.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'Today',
                    value: 'NGN 148,500',
                    footnote: '12 completed jobs | 96% acceptance',
                    icon: Icons.today_outlined,
                    tint: context.hailoTokens.success,
                  ),
                ),
                const SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'This week',
                    value: 'NGN 612,000',
                    footnote: 'Momentum and settlements at a glance.',
                    icon: Icons.bar_chart_rounded,
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: PremiumMetricTile(
                    label: 'Payout readiness',
                    value: 'Healthy',
                    footnote: 'Structured for payout and wallet integrations.',
                    icon: Icons.account_balance_wallet_outlined,
                    tint: context.hailoTokens.warning,
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

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const <Widget>[
            PremiumSectionHeader(
              eyebrow: 'Vehicle and compliance',
              title: 'Keep your driver readiness visible.',
              description:
                  'Vehicle details, documents, and compliance status belong in a dedicated operator profile, not scattered dev buttons.',
            ),
            SizedBox(height: HailoSpacing.lg),
            _DriverSupportPanel(),
          ],
        ),
      ),
    );
  }
}

class _DriverAssignmentsPanel extends StatelessWidget {
  const _DriverAssignmentsPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Assignments',
            title: 'Active jobs slot in here.',
            description:
                'The UI is ready for assigned and available trip cards once live job feeds are connected.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'No active assignment yet',
            subtitle:
                'When a trip is assigned or an offer is accepted, it will appear here with clearer operational context.',
            leadingIcon: Icons.assignment_outlined,
          ),
        ],
      ),
    );
  }
}

class _DriverSupportPanel extends StatelessWidget {
  const _DriverSupportPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Readiness',
            title: 'Vehicle, support, and compliance visibility.',
            description:
                'As backend support expands, this panel will host vehicle readiness, support history, and operator compliance signals.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Vehicle profile',
            subtitle:
                'Primary vehicle details and status are ready to land here.',
            leadingIcon: Icons.directions_car_outlined,
          ),
          SizedBox(height: HailoSpacing.md),
          PremiumListItem(
            title: 'Compliance documents',
            subtitle:
                'Document expiry and readiness can be surfaced without clutter.',
            leadingIcon: Icons.badge_outlined,
          ),
          SizedBox(height: HailoSpacing.md),
          PremiumListItem(
            title: 'Support channel',
            subtitle:
                'Operator help and escalation pathways stay close at hand.',
            leadingIcon: Icons.support_agent_rounded,
          ),
        ],
      ),
    );
  }
}
