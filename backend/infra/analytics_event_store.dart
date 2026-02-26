import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'postgres_provider.dart';
import 'request_context.dart';

typedef AnalyticsWarningSink = void Function(String line);

class AnalyticsEventStore {
  AnalyticsEventStore({
    Database? sqliteDb,
    PostgresProvider? postgresProvider,
    Uuid? uuid,
    DateTime Function()? nowUtc,
    AnalyticsWarningSink? warningSink,
  }) : _sqliteDb = sqliteDb,
       _postgresProvider = postgresProvider,
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _warningSink = warningSink ?? print;

  final Database? _sqliteDb;
  final PostgresProvider? _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final AnalyticsWarningSink _warningSink;

  Future<void> emitFromRequest(
    Request request, {
    required String name,
    Object? properties,
    String? userId,
    String? sessionId,
    DateTime? createdAtUtc,
  }) {
    final contextUserId = request.requestContext.userId?.trim();
    final resolvedUserId =
        _normalizedText(userId) ?? _normalizedText(contextUserId);
    final resolvedSessionId =
        _normalizedText(sessionId) ??
        _normalizedText(request.headers['x-session-id']) ??
        _normalizedText(request.headers['x-client-session-id']);
    return emit(
      name: name,
      userId: resolvedUserId,
      sessionId: resolvedSessionId,
      properties: properties,
      createdAtUtc: createdAtUtc,
    );
  }

  Future<void> emit({
    required String name,
    String? userId,
    String? sessionId,
    Object? properties,
    DateTime? createdAtUtc,
  }) async {
    if (_sqliteDb == null && _postgresProvider == null) {
      return;
    }

    final normalizedName = _normalizedText(name)?.toLowerCase();
    if (normalizedName == null) {
      return;
    }
    final normalizedUserId = _normalizedText(userId);
    final normalizedSessionId = _normalizedText(sessionId);
    final propertiesJson = _encodePropertiesJson(properties);
    final id = _uuid.v4();
    final createdAtIso = (createdAtUtc ?? _nowUtc()).toUtc().toIso8601String();

    final sqliteDb = _sqliteDb;
    if (sqliteDb != null) {
      try {
        await sqliteDb.insert('analytics_events', <String, Object?>{
          'id': id,
          'name': normalizedName,
          'user_id': normalizedUserId,
          'session_id': normalizedSessionId,
          'properties': propertiesJson,
          'created_at': createdAtIso,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } catch (error) {
        _warningSink('WARN: analytics_event_write_failed_sqlite: $error');
      }
      return;
    }

    final postgresProvider = _postgresProvider;
    if (postgresProvider == null) {
      return;
    }
    try {
      await postgresProvider.withConnection(
        (connection) => connection.execute(
          '''
          INSERT INTO analytics_events(
            id,
            name,
            user_id,
            session_id,
            properties,
            created_at
          )
          VALUES(
            @id,
            @name,
            CAST(@user_id AS UUID),
            @session_id,
            CAST(@properties AS JSONB),
            @created_at
          )
          ''',
          substitutionValues: <String, Object?>{
            'id': id,
            'name': normalizedName,
            'user_id': normalizedUserId,
            'session_id': normalizedSessionId,
            'properties': propertiesJson,
            'created_at': DateTime.parse(createdAtIso),
          },
        ),
      );
    } catch (error) {
      _warningSink('WARN: analytics_event_write_failed_postgres: $error');
    }
  }

  String? _encodePropertiesJson(Object? properties) {
    if (properties == null) {
      return null;
    }
    try {
      if (properties is Map ||
          properties is List ||
          properties is String ||
          properties is num ||
          properties is bool) {
        return jsonEncode(properties);
      }
      return jsonEncode(<String, Object?>{'value': properties.toString()});
    } catch (_) {
      return jsonEncode(<String, Object?>{'value': properties.toString()});
    }
  }

  String? _normalizedText(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
