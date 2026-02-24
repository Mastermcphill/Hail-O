import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/rider/documents_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('loads documents and saves a new document', (
    WidgetTester tester,
  ) async {
    final documents = <Map<String, dynamic>>[];
    var getCount = 0;

    final mockClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/me/documents') {
        getCount += 1;
        return _jsonResponse(
          status: 200,
          body: <String, dynamic>{'ok': true, 'documents': documents},
        );
      }

      if (request.method == 'POST' && request.url.path == '/me/documents') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final document = <String, dynamic>{
          ...payload,
          'doc_type': (payload['doc_type'] as String?) ?? 'passport',
          'status': 'verified',
        };
        documents.insert(0, document);
        return _jsonResponse(
          status: 201,
          body: <String, dynamic>{'ok': true, 'document': document},
        );
      }

      return _jsonResponse(
        status: 404,
        body: <String, dynamic>{'ok': false, 'message': 'not found'},
      );
    });

    final apiClient = ApiClient(
      tokenStorage: const _InMemoryTokenStorage(),
      httpClient: mockClient,
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RiderDocumentsScreen(apiClient: apiClient)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No documents saved yet.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'file_ref'),
      'local://passport_front.png',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save Document'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('passport - verified'), findsOneWidget);
    expect(getCount, greaterThanOrEqualTo(2));
  });
}

http.Response _jsonResponse({
  required int status,
  required Map<String, dynamic> body,
}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

class _InMemoryTokenStorage extends TokenStorage {
  const _InMemoryTokenStorage();

  @override
  Future<String?> readToken() async {
    return null;
  }
}
