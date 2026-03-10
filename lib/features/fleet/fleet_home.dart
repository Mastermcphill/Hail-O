import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';

class FleetHome extends StatelessWidget {
  const FleetHome({super.key});

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
                          label: 'Fleet command center',
                          icon: Icons.directions_bus_rounded,
                          backgroundColor: Color(0x29FFFFFF),
                          foregroundColor: Colors.white,
                        ),
                        const SizedBox(height: HailoSpacing.lg),
                        Text(
                          'Run vehicles, drivers, and operations from one elevated workspace.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        Text(
                          'The fleet experience is built like a premium operations cockpit: vehicle visibility, driver coordination, settlement awareness, and compliance posture.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: <Widget>[
                        PremiumMetricTile(
                          label: 'Active vehicles',
                          value: '24',
                          footnote: '18 on route | 6 standby',
                          icon: Icons.directions_bus_filled_outlined,
                        ),
                        const SizedBox(height: HailoSpacing.md),
                        PremiumMetricTile(
                          label: 'Settlement outlook',
                          value: 'NGN 3.4M',
                          footnote:
                              'Rolling weekly view across live operations.',
                          icon: Icons.account_balance_wallet_outlined,
                          tint: context.hailoTokens.success,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Fleet overview',
              title: 'Everything leadership needs at a glance.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: 260,
                  child: PremiumMetricTile(
                    label: 'Drivers active',
                    value: '41',
                    footnote: 'Shift visibility and availability.',
                    icon: Icons.groups_outlined,
                    tint: context.hailoTokens.success,
                  ),
                ),
                const SizedBox(
                  width: 260,
                  child: PremiumMetricTile(
                    label: 'Vehicles active',
                    value: '24',
                    footnote: 'Current live fleet footprint.',
                    icon: Icons.local_shipping_outlined,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: PremiumMetricTile(
                    label: 'Compliance alerts',
                    value: '3',
                    footnote: 'Documents nearing expiry.',
                    icon: Icons.warning_amber_rounded,
                    tint: context.hailoTokens.warning,
                  ),
                ),
                const SizedBox(
                  width: 260,
                  child: PremiumMetricTile(
                    label: 'Operational score',
                    value: '97%',
                    footnote: 'On-time, assignment, and support blend.',
                    icon: Icons.insights_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HailoSpacing.section),
            const PremiumSectionHeader(
              eyebrow: 'Operations',
              title: 'Purpose-built tabs for the fleet organization.',
            ),
            const SizedBox(height: HailoSpacing.lg),
            Wrap(
              spacing: HailoSpacing.md,
              runSpacing: HailoSpacing.md,
              children: const <Widget>[
                SizedBox(width: 540, child: _FleetVehiclesPanel()),
                SizedBox(width: 540, child: _FleetDriversPanel()),
                SizedBox(width: 540, child: _FleetOperationsPanel()),
                SizedBox(width: 540, child: _FleetSettlementPanel()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FleetVehiclesScreen extends StatelessWidget {
  const FleetVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 960),
        child: _FleetVehiclesPanel(),
      ),
    );
  }
}

class FleetDriversScreen extends StatelessWidget {
  const FleetDriversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 960),
        child: _FleetDriversPanel(),
      ),
    );
  }
}

class FleetOperationsScreen extends StatelessWidget {
  const FleetOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(HailoSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 960),
        child: _FleetOperationsPanel(),
      ),
    );
  }
}

class _FleetVehiclesPanel extends StatelessWidget {
  const _FleetVehiclesPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Vehicles',
            title: 'Vehicle roster and readiness.',
            description:
                'The shell is prepared for live vehicle lists, maintenance posture, and activation state without exposing internal admin clutter.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Vehicle management ready',
            subtitle:
                'Live fleet vehicles will appear here with status, route, and readiness context.',
            leadingIcon: Icons.directions_bus_outlined,
          ),
        ],
      ),
    );
  }
}

class _FleetDriversPanel extends StatelessWidget {
  const _FleetDriversPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Drivers',
            title: 'Driver oversight, not a raw internal table.',
            description:
                'This area is designed for assignment posture, availability, and compliance overview as driver data integration expands.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Driver oversight ready',
            subtitle:
                'Assigned, idle, and onboarding driver states can land here clearly.',
            leadingIcon: Icons.groups_outlined,
          ),
        ],
      ),
    );
  }
}

class _FleetOperationsPanel extends StatelessWidget {
  const _FleetOperationsPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Operations',
            title: 'Fleet movement and dispatch visibility.',
            description:
                'Operational health, active corridors, and trip-state visibility can scale here cleanly.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Operations overview ready',
            subtitle:
                'Trip volume, route activity, and issue escalation are structured for this space.',
            leadingIcon: Icons.monitor_heart_outlined,
          ),
        ],
      ),
    );
  }
}

class _FleetSettlementPanel extends StatelessWidget {
  const _FleetSettlementPanel();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          PremiumSectionHeader(
            eyebrow: 'Settlements',
            title: 'Financial overview with transport-grade clarity.',
            description:
                'Settlement tracking, payout readiness, and compliance alerts belong in a premium summary surface.',
          ),
          SizedBox(height: HailoSpacing.lg),
          PremiumListItem(
            title: 'Settlement view ready',
            subtitle:
                'Rolling settlement and payout data will connect here as backend support grows.',
            leadingIcon: Icons.payments_outlined,
          ),
        ],
      ),
    );
  }
}
