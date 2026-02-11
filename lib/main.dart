import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'integrations/mapbox/mapbox_token.dart';
import 'ui/devtools/dev_tools_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (isMapboxTokenConfigured) {
    MapboxOptions.setAccessToken(kMapboxAccessToken);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hail-O Core',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Hail-O Backend Core Bootstrap')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DevToolsHomeScreen(),
                ),
              );
            },
            child: const Text('Open Dev Tools'),
          ),
        ),
      ),
    );
  }
}
