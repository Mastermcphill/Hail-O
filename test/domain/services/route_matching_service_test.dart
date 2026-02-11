import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/models/route_node.dart';
import 'package:hail_o_finance_core/domain/services/route_matching_service.dart';

void main() {
  test('matches calling-at sub-route correctly', () {
    final service = RouteMatchingService();
    final nodes = <RouteNode>[
      RouteNode(
        id: 'n1',
        routeId: 'r1',
        sequenceNo: 1,
        label: 'Lagos',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      RouteNode(
        id: 'n2',
        routeId: 'r1',
        sequenceNo: 2,
        label: 'Ibadan',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      RouteNode(
        id: 'n3',
        routeId: 'r1',
        sequenceNo: 3,
        label: 'Ondo',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      RouteNode(
        id: 'n4',
        routeId: 'r1',
        sequenceNo: 4,
        label: 'Benin',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ];

    expect(
      service.matchesSubRouteByLabels(
        routeNodes: nodes,
        pickupLabel: 'Ibadan',
        dropoffLabel: 'Ondo',
      ),
      true,
    );
    expect(
      service.matchesSubRouteByLabels(
        routeNodes: nodes,
        pickupLabel: 'Benin',
        dropoffLabel: 'Ibadan',
      ),
      false,
    );
  });
}
