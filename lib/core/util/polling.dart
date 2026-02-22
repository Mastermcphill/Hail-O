import 'dart:async';

class PollingController {
  Timer? _timer;
  bool _busy = false;

  Future<void> start({
    required Future<void> Function() onPoll,
    Duration interval = const Duration(seconds: 3),
    bool runImmediately = true,
  }) async {
    stop();
    if (runImmediately) {
      await _safePoll(onPoll);
    }
    _timer = Timer.periodic(interval, (_) {
      _safePoll(onPoll);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  Future<void> _safePoll(Future<void> Function() onPoll) async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await onPoll();
    } finally {
      _busy = false;
    }
  }
}
