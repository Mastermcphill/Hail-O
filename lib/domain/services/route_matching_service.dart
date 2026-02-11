import '../models/route_node.dart';

class RouteMatchingService {
  bool matchesSubRouteByLabels({
    required List<RouteNode> routeNodes,
    required String pickupLabel,
    required String dropoffLabel,
  }) {
    final normalizedPickup = pickupLabel.trim().toLowerCase();
    final normalizedDropoff = dropoffLabel.trim().toLowerCase();
    if (normalizedPickup.isEmpty || normalizedDropoff.isEmpty) {
      return false;
    }

    final sorted = <RouteNode>[...routeNodes]
      ..sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
    final pickupIndex = sorted.indexWhere(
      (node) => node.label.trim().toLowerCase() == normalizedPickup,
    );
    final dropoffIndex = sorted.indexWhere(
      (node) => node.label.trim().toLowerCase() == normalizedDropoff,
    );

    return pickupIndex >= 0 && dropoffIndex >= 0 && pickupIndex < dropoffIndex;
  }

  bool matchesSubRouteByNodeId({
    required List<RouteNode> routeNodes,
    required String pickupNodeId,
    required String dropoffNodeId,
  }) {
    final sorted = <RouteNode>[...routeNodes]
      ..sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
    final pickupIndex = sorted.indexWhere((node) => node.id == pickupNodeId);
    final dropoffIndex = sorted.indexWhere((node) => node.id == dropoffNodeId);
    return pickupIndex >= 0 && dropoffIndex >= 0 && pickupIndex < dropoffIndex;
  }
}
