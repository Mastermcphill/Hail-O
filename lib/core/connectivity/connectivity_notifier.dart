import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class ConnectivityProbe {
  Future<List<ConnectivityResult>> check();
  Stream<List<ConnectivityResult>> get changes;
}

class ConnectivityPlusProbe implements ConnectivityProbe {
  ConnectivityPlusProbe({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> check() => _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}

class ConnectivityNotifier extends ChangeNotifier {
  ConnectivityNotifier({ConnectivityProbe? probe})
    : _probe = probe ?? ConnectivityPlusProbe();

  final ConnectivityProbe _probe;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  Future<void> start() async {
    final initial = await _probe.check();
    _applyState(initial);
    _subscription = _probe.changes.listen(_applyState);
  }

  void _applyState(List<ConnectivityResult> states) {
    final offline =
        states.isEmpty ||
        states.every((state) => state == ConnectivityResult.none);
    if (_isOffline == offline) {
      return;
    }
    _isOffline = offline;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
