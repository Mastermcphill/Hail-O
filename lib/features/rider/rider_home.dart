import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RiderHome extends StatelessWidget {
  const RiderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Rider Dashboard',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  context.go('/rider/request');
                },
                child: const Text('Request Ride'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () async {
                  final rideId = await _promptForRideId(
                    context,
                    title: 'Open Ride Status',
                  );
                  if (rideId == null || rideId.isEmpty || !context.mounted) {
                    return;
                  }
                  context.go('/rider/status/${Uri.encodeComponent(rideId)}');
                },
                child: const Text('Open Ride Status (paste ride id)'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () {
                  context.go('/rider/next-of-kin');
                },
                child: const Text('Next-of-kin'),
              ),
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
