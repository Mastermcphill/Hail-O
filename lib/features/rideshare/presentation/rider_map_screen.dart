import 'package:flutter/material.dart';

import '../../../domain/models/latlng.dart';
import '../../../integrations/mapbox/mapbox_map_widget.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/premium_ui.dart';

class RiderMapScreen extends StatelessWidget {
  const RiderMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PremiumSectionHeader(
                eyebrow: 'Network map',
                title: 'See the mobility network as a living system.',
                description:
                    'Nearby vehicles, route corridors, and long-distance availability all belong in one calm map surface.',
              ),
              const SizedBox(height: HailoSpacing.lg),
              SizedBox(
                height: 420,
                child: PremiumPanel(
                  padding: const EdgeInsets.all(HailoSpacing.sm),
                  child: ClipRRect(
                    borderRadius: HailoRadii.md,
                    child: const MapboxMapWidget(
                      initialCenter: LatLng(
                        latitude: 6.5244,
                        longitude: 3.3792,
                      ),
                      initialZoom: 9.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: HailoSpacing.lg),
              Wrap(
                spacing: HailoSpacing.md,
                runSpacing: HailoSpacing.md,
                children: const <Widget>[
                  SizedBox(
                    width: 320,
                    child: PremiumMetricTile(
                      label: 'Nearby city rides',
                      value: '14 vehicles',
                      footnote:
                          'Live and simulated routing merge here until deeper feeds land.',
                      icon: Icons.local_taxi_outlined,
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: PremiumMetricTile(
                      label: 'Inter-city corridor',
                      value: 'Abuja - Kaduna',
                      footnote:
                          'Premium road network route highlighted for scheduled travel.',
                      icon: Icons.alt_route_rounded,
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: PremiumMetricTile(
                      label: 'Cross-border readiness',
                      value: 'Trusted routes only',
                      footnote:
                          'Border notes and travel checks will surface here when data expands.',
                      icon: Icons.public_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
