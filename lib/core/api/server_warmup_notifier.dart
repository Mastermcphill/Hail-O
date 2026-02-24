import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_paths.dart';

class ServerWarmupNotifier extends ChangeNotifier {
  bool _isWarming = false;
  bool _started = false;
  Future<void>? _warmupFuture;

  bool get isWarming => _isWarming;

  Future<void> start(ApiClient apiClient) {
    if (_started) {
      return _warmupFuture ?? Future<void>.value();
    }
    _started = true;
    _warmupFuture = _runWarmup(apiClient);
    return _warmupFuture!;
  }

  Future<void> _runWarmup(ApiClient apiClient) async {
    var bannerShown = false;
    final timer = Timer(const Duration(milliseconds: 1200), () {
      _isWarming = true;
      bannerShown = true;
      notifyListeners();
    });

    try {
      await apiClient.get(ApiPaths.health);
    } catch (_) {
      // Warmup is best-effort only.
    } finally {
      timer.cancel();
      if (bannerShown && _isWarming) {
        _isWarming = false;
        notifyListeners();
      }
    }
  }
}
