import '../../../lib/domain/services/ride_api_flow_service.dart';

abstract class RideRequestMetadataStore
    implements RideRequestMetadataExternalStore {
  const RideRequestMetadataStore();
}

abstract class OperationalRecordStore
    implements OperationalRecordExternalStore {
  const OperationalRecordStore();
}
