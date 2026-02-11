import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/models/route_node.dart';
import 'package:hail_o_finance_core/domain/models/vehicle.dart';
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

  test('luggage filter excludes sedan and hatchback when luggage > 2', () {
    final service = RouteMatchingService();
    final now = DateTime.utc(2026, 1, 1);
    final vehicles = <Vehicle>[
      Vehicle(
        id: 'v1',
        driverId: 'd1',
        type: VehicleType.sedan,
        seatCount: 4,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      Vehicle(
        id: 'v2',
        driverId: 'd2',
        type: VehicleType.hatchback,
        seatCount: 4,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      Vehicle(
        id: 'v3',
        driverId: 'd3',
        type: VehicleType.suv,
        seatCount: 6,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      Vehicle(
        id: 'v4',
        driverId: 'd4',
        type: VehicleType.bus,
        seatCount: 14,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final filtered = service.filterEligibleVehiclesByLuggage(
      vehicles: vehicles,
      luggageCount: 3,
    );
    expect(
      filtered.map((vehicle) => vehicle.type).toList(growable: false),
      <VehicleType>[VehicleType.suv, VehicleType.bus],
    );

    final unfiltered = service.filterEligibleVehiclesByLuggage(
      vehicles: vehicles,
      luggageCount: 2,
    );
    expect(unfiltered.length, 4);
  });
}
