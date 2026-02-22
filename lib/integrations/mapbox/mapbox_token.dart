const String kMapboxAccessToken = String.fromEnvironment(
  'MAPBOX_TOKEN',
  defaultValue: 'PLEASE_SET_TOKEN',
);

bool get isMapboxTokenConfigured =>
    kMapboxAccessToken.trim().isNotEmpty &&
    kMapboxAccessToken != 'PLEASE_SET_TOKEN';
