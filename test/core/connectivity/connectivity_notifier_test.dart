import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/connectivity/connectivity_notifier.dart';

void main() {
  test('starts offline when probe reports no connectivity', () async {
    final probe = _FakeConnectivityProbe(
      initial: <ConnectivityResult>[ConnectivityResult.none],
    );
    final notifier = ConnectivityNotifier(probe: probe);
    addTearDown(notifier.dispose);

    await notifier.start();

    expect(notifier.isOffline, isTrue);
  });

  test('transitions online when connectivity returns', () async {
    final probe = _FakeConnectivityProbe(
      initial: <ConnectivityResult>[ConnectivityResult.none],
    );
    final notifier = ConnectivityNotifier(probe: probe);
    addTearDown(notifier.dispose);

    await notifier.start();
    expect(notifier.isOffline, isTrue);

    probe.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.isOffline, isFalse);
  });
}

class _FakeConnectivityProbe implements ConnectivityProbe {
  _FakeConnectivityProbe({required List<ConnectivityResult> initial})
    : _initial = initial;

  final List<ConnectivityResult> _initial;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> check() async {
    return _initial;
  }

  @override
  Stream<List<ConnectivityResult>> get changes => _controller.stream;

  void emit(List<ConnectivityResult> values) {
    _controller.add(values);
  }
}
