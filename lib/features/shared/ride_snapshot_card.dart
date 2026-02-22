import 'package:flutter/material.dart';

import 'json_view.dart';

class RideSnapshotCard extends StatefulWidget {
  const RideSnapshotCard({
    super.key,
    required this.snapshot,
  });

  final Map<String, dynamic> snapshot;

  @override
  State<RideSnapshotCard> createState() => _RideSnapshotCardState();
}

class _RideSnapshotCardState extends State<RideSnapshotCard> {
  bool _showJson = false;

  @override
  Widget build(BuildContext context) {
    final ride = _asMap(widget.snapshot['ride']);
    final rideId = _pickString(<dynamic>[
      widget.snapshot['ride_id'],
      ride['id'],
    ]);
    final status = _pickString(<dynamic>[
      widget.snapshot['status'],
      widget.snapshot['state'],
      widget.snapshot['ride_status'],
      ride['status'],
      ride['state'],
      ride['ride_status'],
    ]);
    final riderId = _pickString(<dynamic>[
      widget.snapshot['rider_id'],
      ride['rider_id'],
    ]);
    final driverId = _pickString(<dynamic>[
      widget.snapshot['driver_id'],
      ride['driver_id'],
    ]);
    final money = _collectMoneyFields(ride, widget.snapshot);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _InfoRow(label: 'Ride id', value: rideId ?? '-'),
            const SizedBox(height: 8),
            _InfoRow(label: 'Status', value: status ?? '-'),
            const SizedBox(height: 8),
            _InfoRow(label: 'Rider id', value: riderId ?? '-'),
            const SizedBox(height: 8),
            _InfoRow(label: 'Driver id', value: driverId ?? '-'),
            if (money.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              Text(
                'Money',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final entry in money.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InfoRow(
                    label: entry.key,
                    value: entry.value.toString(),
                  ),
                ),
            ],
            const Divider(height: 24),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showJson = !_showJson;
                });
              },
              icon: Icon(_showJson ? Icons.expand_less : Icons.expand_more),
              label: Text(_showJson ? 'Hide JSON' : 'Show JSON'),
            ),
            if (_showJson) JsonView(data: widget.snapshot),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(value)),
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
