import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../server/middleware/admin_emergency_access_middleware.dart';
import 'postgres_provider.dart';
import 'request_context.dart';

typedef AuditLogWarningSink = void Function(String line);

class AuditLogStore {
  AuditLogStore({
    Database? sqliteDb,
    PostgresProvider? postgresProvider,
    bool trustProxyHeaders = true,
    Uuid? uuid,
    DateTime Function()? nowUtc,
    AuditLogWarningSink? warningSink,
  }) : _sqliteDb = sqliteDb,
       _postgresProvider = postgresProvider,
       _trustProxyHeaders = trustProxyHeaders,
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _warningSink = warningSink ?? print;

  final Database? _sqliteDb;
  final PostgresProvider? _postgresProvider;
  final bool _trustProxyHeaders;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final AuditLogWarningSink _warningSink;

  Future<void> recordFromRequest(
    Request request, {
    required String action,
    required String resourceType,
    required String resourceId,
    Object? metadata,
  }) {
    final actorType = requestUsedAdminToken(request) ? 'admin_token' : 'user';
    final actorUserId = actorType == 'admin_token'
        ? null
        : request.requestContext.userId;
    return record(
      actorType: actorType,
      actorUserId: actorUserId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      ip: _extractClientIp(request),
      userAgent: request.headers['user-agent'],
      metadata: metadata,
    );
  }

  Future<void> record({
    required String actorType,
    String? actorUserId,
    required String action,
    required String resourceType,
    required String resourceId,
    String? ip,
    String? userAgent,
    Object? metadata,
    DateTime? createdAtUtc,
  }) async {
    if (_sqliteDb == null && _postgresProvider == null) {
      return;
    }

    final normalizedAction = _normalizedText(action) ?? 'unknown_action';
    final normalizedResourceType =
        _normalizedText(resourceType) ?? 'unknown_resource';
    final normalizedResourceId = _normalizedText(resourceId) ?? 'unknown';
    final normalizedActorType = _normalizedActorType(actorType);
    final normalizedActorUserId = _normalizedText(actorUserId);
    final normalizedIp = _normalizedText(ip);
    final normalizedUserAgent = _normalizedText(userAgent);
    final metadataJson = _encodeMetadataJson(metadata);
    final createdAtIso = (createdAtUtc ?? _nowUtc()).toUtc().toIso8601String();
    final id = _uuid.v4();

    final sqliteDb = _sqliteDb;
    if (sqliteDb != null) {
      try {
        await sqliteDb.insert('audit_logs', <String, Object?>{
          'id': id,
          'actor_user_id': normalizedActorUserId,
          'actor_type': normalizedActorType,
          'action': normalizedAction,
          'resource_type': normalizedResourceType,
          'resource_id': normalizedResourceId,
          'ip': normalizedIp,
          'user_agent': normalizedUserAgent,
          'metadata': metadataJson,
          'created_at': createdAtIso,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } catch (error) {
        _warningSink('WARN: audit_log_write_failed_sqlite: $error');
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
          INSERT INTO audit_logs(
            id,
            actor_user_id,
            actor_type,
            action,
            resource_type,
            resource_id,
            ip,
            user_agent,
            metadata,
            created_at
          )
          VALUES(
            @id,
            @actor_user_id,
            @actor_type,
            @action,
            @resource_type,
            @resource_id,
            @ip,
            @user_agent,
            CAST(@metadata AS JSONB),
            @created_at
          )
          ''',
          substitutionValues: <String, Object?>{
            'id': id,
            'actor_user_id': normalizedActorUserId,
            'actor_type': normalizedActorType,
            'action': normalizedAction,
            'resource_type': normalizedResourceType,
            'resource_id': normalizedResourceId,
            'ip': normalizedIp,
            'user_agent': normalizedUserAgent,
            'metadata': metadataJson,
            'created_at': DateTime.parse(createdAtIso),
          },
        ),
      );
    } catch (error) {
      _warningSink('WARN: audit_log_write_failed_postgres: $error');
    }
  }

  String _normalizedActorType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'admin_token') {
      return 'admin_token';
    }
    return 'user';
  }

  String? _encodeMetadataJson(Object? metadata) {
    if (metadata == null) {
      return null;
    }
    try {
      if (metadata is Map ||
          metadata is List ||
          metadata is num ||
          metadata is bool) {
        return jsonEncode(metadata);
      }
      if (metadata is String) {
        final normalized = metadata.trim();
        if (normalized.isEmpty) {
          return null;
        }
        return jsonEncode(<String, Object?>{'value': normalized});
      }
      return jsonEncode(<String, Object?>{'value': metadata.toString()});
    } catch (_) {
      return jsonEncode(<String, Object?>{'value': metadata.toString()});
    }
  }

  String _extractClientIp(Request request) {
    if (_trustProxyHeaders) {
      final forwarded = request.headers['x-forwarded-for']?.trim() ?? '';
      if (forwarded.isNotEmpty) {
        return forwarded.split(',').first.trim();
      }
      final realIp = request.headers['x-real-ip']?.trim() ?? '';
      if (realIp.isNotEmpty) {
        return realIp;
      }
    }

    final connectionInfo = request.context['shelf.io.connection_info'];
    if (connectionInfo is HttpConnectionInfo) {
      final address = connectionInfo.remoteAddress.address.trim();
      if (address.isNotEmpty) {
        return address;
      }
    }
    return 'unknown';
  }

  String? _normalizedText(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
