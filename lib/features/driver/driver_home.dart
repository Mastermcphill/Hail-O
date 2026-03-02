import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import 'driver_autosave_panel.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Driver Dashboard',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  context.go('/driver/route-chain');
                },
                child: const Text('Create Route Chain'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  final rideId = await _promptForRideId(
                    context,
                    title: 'Offer on Ride',
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (rideId == null || rideId.isEmpty) {
                    context.go('/driver/offer');
                    return;
                  }
                  context.go('/driver/offer/${Uri.encodeComponent(rideId)}');
                },
                child: const Text('Offer on Ride (paste ride id)'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  final rideId = await _promptForRideId(
                    context,
                    title: 'Ride Ops',
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (rideId == null || rideId.isEmpty) {
                    context.go('/driver/ride-ops');
                    return;
                  }
                  context.go('/driver/ride-ops/${Uri.encodeComponent(rideId)}');
                },
                child: const Text('Ride Ops (paste ride id)'),
              ),
              const SizedBox(height: 18),
              DriverAutosavePanel(apiClient: apiClient),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptForRideId(
  BuildContext context, {
  required String title,
}) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ride_id',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Open'),
          ),
        ],
      );
    },
  );
}
