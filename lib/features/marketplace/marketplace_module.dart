import '../../core/api/api_client.dart';
import 'data/marketplace_local_store.dart';
import 'data/marketplace_repository_http.dart';
import 'state/marketplace_controller.dart';

class MarketplaceModule {
  MarketplaceModule({required ApiClient apiClient})
    : controller = MarketplaceController(
        repository: MarketplaceRepositoryHttp(apiClient: apiClient),
        localStore: MarketplaceLocalStore(),
      );

  final MarketplaceController controller;

  void dispose() {
    controller.dispose();
  }
}
