import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../marketplace/data/marketplace_dev_settings.dart';

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
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () {
                  context.go('/marketplace/offers');
                },
                child: const Text('Marketplace'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () {
                  context.go('/marketplace/billing');
                },
                child: const Text('Marketplace Billing'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () {
                  context.go('/marketplace/invites');
                },
                child: const Text('Marketplace Invites'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketplaceDebugSection extends StatefulWidget {
  const _MarketplaceDebugSection();

  @override
  State<_MarketplaceDebugSection> createState() =>
      _MarketplaceDebugSectionState();
}

class _MarketplaceDebugSectionState extends State<_MarketplaceDebugSection> {
  final MarketplaceDevSettings _settings = const MarketplaceDevSettings();
  bool _loading = true;
  bool _saving = false;
  bool _useLiveApi = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _settings.readUseLiveApi();
    if (!mounted) {
      return;
    }
    setState(() {
      _useLiveApi = value;
      _loading = false;
    });
  }

  Future<void> _updateLiveApiPreference(bool value) async {
    setState(() {
      _useLiveApi = value;
      _saving = true;
    });

    await _settings.writeUseLiveApi(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Marketplace Debug',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Marketplace: Use Live API'),
              subtitle: const Text('When off, mock repository stays primary.'),
              value: _useLiveApi,
              onChanged: (_loading || _saving)
                  ? null
                  : (value) {
                      _updateLiveApiPreference(value);
                    },
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              onPressed: () {
                context.go('/marketplace/offers');
              },
              child: const Text('Marketplace (Debug)'),
            ),
          ],
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
