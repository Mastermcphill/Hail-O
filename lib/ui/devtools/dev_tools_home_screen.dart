import 'package:flutter/material.dart';

import 'map_preview_screen.dart';
import 'offline_map_download_screen.dart';
import 'offline_regions_screen.dart';

class DevToolsHomeScreen extends StatelessWidget {
  const DevToolsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hail-O Dev Tools')),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text('Offline Download'),
            subtitle: const Text('Download style pack + tile region'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OfflineMapDownloadScreen(),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Offline Regions'),
            subtitle: const Text('List and delete offline regions'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OfflineRegionsScreen(),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Map Preview'),
            subtitle: const Text('Preview map + GPS + offline status'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MapPreviewScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
