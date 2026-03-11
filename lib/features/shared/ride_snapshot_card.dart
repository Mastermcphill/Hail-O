import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/trust_badge.dart';
import 'json_view.dart';

class RideSnapshotCard extends StatefulWidget {
  const RideSnapshotCard({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  State<RideSnapshotCard> createState() => _RideSnapshotCardState();
}

class _RideSnapshotCardState extends State<RideSnapshotCard> {
  bool _showJson = false;

  @override
  Widget build(BuildContext context) {
    final ride = _asMap(widget.snapshot['ride']);
    final rideId =
        _pickString(<dynamic>[widget.snapshot['ride_id'], ride['id']]) ?? '-';
    final status =
        _pickString(<dynamic>[
          widget.snapshot['status'],
          widget.snapshot['state'],
          ride['status'],
          ride['state'],
        ]) ??
        'Pending';
    final driverId =
        _pickString(<dynamic>[
          widget.snapshot['driver_id'],
          ride['driver_id'],
        ]) ??
        'Assigned operator';
    final money = _collectMoneyFields(ride, widget.snapshot);

    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PremiumSectionHeader(
            eyebrow: 'Trip snapshot',
            title: 'Live ride details in one place.',
            description:
                'Status, operator assignment, and fare context stay visible without exposing raw internal tooling.',
          ),
          const SizedBox(height: HailoSpacing.lg),
          Wrap(
            spacing: HailoSpacing.xs,
            runSpacing: HailoSpacing.xs,
            children: const <Widget>[
              TrustBadge(
                label: 'Escrow protected',
                icon: Icons.lock_clock_outlined,
              ),
              TrustBadge(
                label: 'Trip-linked receipt',
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
          const SizedBox(height: HailoSpacing.lg),
          _InfoRow(label: 'Ride ID', value: rideId),
          const SizedBox(height: HailoSpacing.sm),
          _InfoRow(label: 'Status', value: status),
          const SizedBox(height: HailoSpacing.sm),
          _InfoRow(label: 'Operator', value: driverId),
          if (money.isNotEmpty) ...<Widget>[
            const SizedBox(height: HailoSpacing.lg),
            Text(
              'Fare and protection',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: HailoSpacing.sm),
            for (final entry in money.entries) ...<Widget>[
              _InfoRow(label: entry.key, value: entry.value.toString()),
              const SizedBox(height: HailoSpacing.xs),
            ],
          ],
          const SizedBox(height: HailoSpacing.md),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showJson = !_showJson;
              });
            },
            icon: Icon(
              _showJson ? Icons.expand_less : Icons.data_object_rounded,
            ),
            label: Text(_showJson ? 'Hide raw snapshot' : 'Show raw snapshot'),
          ),
          if (_showJson) JsonView(data: widget.snapshot),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

String? _pickString(List<dynamic> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

Map<String, dynamic> _collectMoneyFields(
  Map<String, dynamic> ride,
  Map<String, dynamic> snapshot,
) {
  final fields = <String>[
    'quoted_fare_minor',
    'total_fare_minor',
    'base_fare_minor',
    'premium_markup_minor',
    'connection_fee_minor',
    'penalty_minor',
  ];
  final output = <String, dynamic>{};
  for (final field in fields) {
    final value = ride[field] ?? snapshot[field];
    if (value != null) {
      output[field] = value;
    }
  }
  final escrow = _asMap(snapshot['escrow']);
  if (escrow['amount_minor'] != null) {
    output['escrow.amount_minor'] = escrow['amount_minor'];
  }
  final payout = _asMap(snapshot['payout']);
  if (payout['amount_minor'] != null) {
    output['payout.amount_minor'] = payout['amount_minor'];
  }
  return output;
}
