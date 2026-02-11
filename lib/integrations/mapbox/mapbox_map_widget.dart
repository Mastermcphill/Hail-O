import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/latlng.dart';
import 'mapbox_token.dart';

class MapboxMapWidget extends StatefulWidget {
  const MapboxMapWidget({
    super.key,
    required this.initialCenter,
    this.initialZoom = 12,
    this.styleUri = MapboxStyles.STANDARD,
    this.showUserLocation = false,
    this.onMapCreated,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final String styleUri;
  final bool showUserLocation;
  final ValueChanged<MapboxMap>? onMapCreated;

  @override
  State<MapboxMapWidget> createState() => _MapboxMapWidgetState();
}

class _MapboxMapWidgetState extends State<MapboxMapWidget> {
  @override
  void initState() {
    super.initState();
    if (isMapboxTokenConfigured) {
      MapboxOptions.setAccessToken(kMapboxAccessToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const Center(
        child: Text('Mapbox map preview is supported on Android/iOS only.'),
      );
    }
    if (!isMapboxTokenConfigured) {
      return const Center(
        child: Text(
          'Mapbox token missing. TODO: pass --dart-define=MAPBOX_TOKEN=...',
        ),
      );
    }

    return MapWidget(
      styleUri: widget.styleUri,
      cameraOptions: CameraOptions(
        center: Point(
          coordinates: Position(
            widget.initialCenter.longitude,
            widget.initialCenter.latitude,
          ),
        ),
        zoom: widget.initialZoom,
      ),
      onMapCreated: (map) async {
        if (widget.showUserLocation) {
          await map.location.updateSettings(
            LocationComponentSettings(
              enabled: true,
              pulsingEnabled: true,
              puckBearingEnabled: true,
            ),
          );
        }
        widget.onMapCreated?.call(map);
      },
    );
  }
}
