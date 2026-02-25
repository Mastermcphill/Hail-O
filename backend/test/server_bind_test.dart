import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../main.dart' as backend_main;

void main() {
  test(
    'bindServerOrExit does not read address/port until bind completes',
    () async {
      final bindGate = Completer<void>();
      var bindCompleted = false;
      final fakeServer = _OrderCheckingHttpServer(
        canReadSocketInfo: () => bindCompleted,
      );
      final events = <Map<String, Object?>>[];
      var served = false;

      Future<HttpServer> binder(String host, int port) async {
        await bindGate.future;
        bindCompleted = true;
        return fakeServer;
      }

      final bindFuture = backend_main.bindServerOrExit(
        handler: (request) async => Response.ok('ok'),
        host: '0.0.0.0',
        port: 8080,
        binder: binder,
        serveRequests: (_, __) => served = true,
        reportError: (_, __) async {},
        logEvent: events.add,
        exitProcess: (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(fakeServer.addressReadCount, 0);
      expect(fakeServer.portReadCount, 0);
      expect(served, isFalse);
      expect(events, isEmpty);

      bindGate.complete();
      final server = await bindFuture;
      expect(identical(server, fakeServer), isTrue);
      expect(served, isTrue);
      expect(fakeServer.addressReadCount, 1);
      expect(fakeServer.portReadCount, 1);
      expect(events, hasLength(1));
      expect(events.first['event'], 'server_listen');
      expect(events.first['host'], '127.0.0.1');
      expect(events.first['port'], 8080);
    },
  );

  test('bindServerOrExit logs and exits when bind fails', () async {
    final events = <Map<String, Object?>>[];
    var reportedError = false;
    var exitCode = 0;
    var served = false;

    Future<HttpServer> binder(String host, int port) async {
      throw const HttpException('bind failed');
    }

    await expectLater(
      backend_main.bindServerOrExit(
        handler: (request) async => Response.ok('ok'),
        host: '0.0.0.0',
        port: 8080,
        binder: binder,
        serveRequests: (_, __) => served = true,
        reportError: (_, __) async => reportedError = true,
        logEvent: events.add,
        exitProcess: (code) => exitCode = code,
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains('ServerBindFailure('),
          'ServerBindFailure',
        ),
      ),
    );

    expect(served, isFalse);
    expect(reportedError, isTrue);
    expect(exitCode, 1);
    expect(events, hasLength(1));
    expect(events.first['event'], 'server_bind_failed');
    expect(events.first['host'], '0.0.0.0');
    expect(events.first['port'], 8080);
    expect((events.first['error'] as String?)?.isNotEmpty, isTrue);
  });
}

class _OrderCheckingHttpServer implements HttpServer {
  _OrderCheckingHttpServer({required this.canReadSocketInfo});

  final bool Function() canReadSocketInfo;
  int addressReadCount = 0;
  int portReadCount = 0;

  @override
  InternetAddress get address {
    if (!canReadSocketInfo()) {
      throw StateError('address read before bind completed');
    }
    addressReadCount += 1;
    return InternetAddress.loopbackIPv4;
  }

  @override
  int get port {
    if (!canReadSocketInfo()) {
      throw StateError('port read before bind completed');
    }
    portReadCount += 1;
    return 8080;
  }

  @override
  Future<void> close({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Unexpected HttpServer member: $invocation');
  }
}
