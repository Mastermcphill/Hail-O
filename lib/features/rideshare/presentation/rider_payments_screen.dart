import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/premium_ui.dart';
import '../../../widgets/trust_badge.dart';

class RiderPaymentsScreen extends StatelessWidget {
  const RiderPaymentsScreen({super.key});

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
                eyebrow: 'Payments',
                title: 'Receipts, booking history, and escrow clarity.',
                description:
                    'This is a booking and receipt surface, not a fake stored-balance promise. Payment protection stays visible across every trip.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              PremiumPanel(
                gradient: context.hailoTokens.heroGradient,
                borderColor: Colors.white.withValues(alpha: 0.10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    PremiumPill(
                      label: 'Escrow Payment Protection',
                      icon: Icons.lock_clock_outlined,
                      backgroundColor: Color(0x24FFFFFF),
                      foregroundColor: Colors.white,
                    ),
                    SizedBox(height: HailoSpacing.md),
                    Text(
                      'Your payment is held securely until the journey begins.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: HailoSpacing.sm),
                    Text(
                      'Trip receipts, protected booking states, and operator payment milestones appear here in one clear account hub.',
                      style: TextStyle(
                        color: Color(0xE0FFFFFF),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HailoSpacing.lg),
              Wrap(
                spacing: HailoSpacing.xs,
                runSpacing: HailoSpacing.xs,
                children: const <Widget>[
                  TrustBadge(
                    label: 'Protected booking',
                    icon: Icons.shield_outlined,
                  ),
                  TrustBadge(
                    label: 'Receipt ready',
                    icon: Icons.receipt_long_outlined,
                  ),
                  TrustBadge(
                    label: 'Trip-linked payment',
                    icon: Icons.route_outlined,
                  ),
                ],
              ),
              const SizedBox(height: HailoSpacing.lg),
              PremiumPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    PremiumSectionHeader(
                      eyebrow: 'Recent payment activity',
                      title: 'Purpose-built for protected trip receipts.',
                      description:
                          'Wallet balances are intentionally not fabricated here. This panel is ready for real booking payment records and receipt links.',
                    ),
                    SizedBox(height: HailoSpacing.lg),
                    PremiumListItem(
                      title: 'No recent receipts yet',
                      subtitle:
                          'When you complete protected bookings, receipts and escrow release states will appear here.',
                      leadingIcon: Icons.payments_outlined,
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
