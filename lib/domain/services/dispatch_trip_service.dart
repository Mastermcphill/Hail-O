import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../errors/domain_errors.dart';

class DispatchTripService {
  DispatchTripService(this._db, {Uuid? uuid, DateTime Function()? nowUtc})
    : _uuid = uuid ?? const Uuid(),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database _db;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  static const Set<String> knownStatuses = <String>{
    'created',
    'searching',
    'assigned',
    'enroute_pickup',
    'picked_up',
    'enroute_dropoff',
    'delivered',
    'canceled',
  };

  static const Map<String, Set<String>> _allowedTransitions =
      <String, Set<String>>{
        'created': <String>{'searching', 'canceled'},
        'searching': <String>{'assigned', 'canceled'},
        'assigned': <String>{'enroute_pickup', 'canceled'},
        'enroute_pickup': <String>{'picked_up', 'canceled'},
        'picked_up': <String>{'enroute_dropoff', 'canceled'},
        'enroute_dropoff': <String>{'delivered', 'canceled'},
        'delivered': <String>{},
        'canceled': <String>{},
      };

  Future<Map<String, Object?>> createTrip({
    required String userId,
    required Map<String, Object?> payload,
  }) async {
    final pickupRaw = _asObjectMap(payload['pickup']);
    final dropoffRaw = _asObjectMap(payload['dropoff']);
    if (pickupRaw == null) {
      throw const DomainInvariantError(code: 'pickup_required');
    }
    if (dropoffRaw == null) {
      throw const DomainInvariantError(code: 'dropoff_required');
    }

    final pickupLat = _readCoordinate(
      pickupRaw['lat'],
      codeIfMissing: 'pickup_lat_required',
      codeIfInvalid: 'invalid_pickup_lat',
      min: -90,
      max: 90,
    );
    final pickupLng = _readCoordinate(
      pickupRaw['lng'],
      codeIfMissing: 'pickup_lng_required',
      codeIfInvalid: 'invalid_pickup_lng',
      min: -180,
      max: 180,
    );
    final dropoffLat = _readCoordinate(
      dropoffRaw['lat'],
      codeIfMissing: 'dropoff_lat_required',
      codeIfInvalid: 'invalid_dropoff_lat',
      min: -90,
      max: 90,
    );
    final dropoffLng = _readCoordinate(
      dropoffRaw['lng'],
      codeIfMissing: 'dropoff_lng_required',
      codeIfInvalid: 'invalid_dropoff_lng',
      min: -180,
      max: 180,
    );

    final pickupAddress = _optionalText(
      pickupRaw['address'],
      codeIfInvalid: 'invalid_pickup_address',
    );
    final dropoffAddress = _optionalText(
      dropoffRaw['address'],
      codeIfInvalid: 'invalid_dropoff_address',
    );
    final notes = _optionalText(
      payload['notes'],
      codeIfInvalid: 'invalid_notes',
    );
    final scheduledAt = _optionalIsoUtc(
      payload['scheduled_at'],
      codeIfInvalid: 'invalid_scheduled_at',
    );

    final tripId = _uuid.v4();
    final eventId = _uuid.v4();
    final nowIso = _nowUtc().toUtc().toIso8601String();

    await _db.transaction((txn) async {
      await txn.insert('trips', <String, Object?>{
        'id': tripId,
        'user_id': userId,
        'status': 'created',
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'pickup_address': pickupAddress,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'dropoff_address': dropoffAddress,
        'notes': notes,
        'scheduled_at': scheduledAt,
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.insert('trip_events', <String, Object?>{
        'id': eventId,
        'trip_id': tripId,
        'actor_user_id': userId,
        'from_status': null,
        'to_status': 'created',
        'metadata': null,
        'created_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });

    final trip = await getTrip(
      tripId: tripId,
      requesterUserId: userId,
      requesterIsAdmin: false,
    );
    return <String, Object?>{'trip': trip};
  }

  Future<Map<String, Object?>> getTrip({
    required String tripId,
    required String requesterUserId,
    required bool requesterIsAdmin,
  }) async {
    final tripRow = await _findAccessibleTripRow(
      tripId: tripId,
      requesterUserId: requesterUserId,
      requesterIsAdmin: requesterIsAdmin,
    );
    if (tripRow == null) {
      throw const DomainInvariantError(code: 'trip_not_found');
    }
    return _tripPayloadFromRow(tripRow);
  }

  Future<Map<String, Object?>> listTrips({
    required String requesterUserId,
    String? status,
    required int limit,
    String? cursor,
  }) async {
    final normalizedStatus = _normalizeStatusFilter(status);
    final decodedCursor = _decodeCursor(cursor);
    final whereParts = <String>['user_id = ?'];
    final whereArgs = <Object>[requesterUserId];
    if (normalizedStatus != null) {
      whereParts.add('status = ?');
      whereArgs.add(normalizedStatus);
    }
    if (decodedCursor != null) {
      whereParts.add('(created_at < ? OR (created_at = ? AND id < ?))');
      whereArgs.add(decodedCursor.createdAtIso);
      whereArgs.add(decodedCursor.createdAtIso);
      whereArgs.add(decodedCursor.tripId);
    }

    final rows = await _db.query(
      'trips',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: limit + 1,
    );

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.take(limit).toList(growable: false) : rows;
    final trips = pageRows
        .map((row) => _tripPayloadFromRow(Map<String, Object?>.from(row)))
        .toList(growable: false);

    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      nextCursor = _encodeCursor(
        (last['created_at'] as String?) ?? '',
        (last['id'] as String?) ?? '',
      );
    }

    return <String, Object?>{
      'trips': trips,
      if (nextCursor != null) 'next_cursor': nextCursor,
    };
  }

  Future<Map<String, Object?>> transitionStatus({
    required String tripId,
    required String actorUserId,
    required bool actorIsAdmin,
    required Map<String, Object?> payload,
  }) async {
    final targetStatus = _normalizeStatus(payload['status']);
    final metadataEncoded = _encodeMetadata(payload['metadata']);
    final nowIso = _nowUtc().toUtc().toIso8601String();

    Map<String, Object?>? updatedTrip;
    Map<String, Object?>? createdEvent;

    await _db.transaction((txn) async {
      final tripRows = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        limit: 1,
      );
      if (tripRows.isEmpty) {
        throw const DomainInvariantError(code: 'trip_not_found');
      }
      final trip = Map<String, Object?>.from(tripRows.first);
      final ownerUserId = (trip['user_id'] as String?) ?? '';
      if (!actorIsAdmin && ownerUserId != actorUserId) {
        throw const DomainInvariantError(code: 'trip_not_found');
      }

      final fromStatus =
          (trip['status'] as String?)?.trim().toLowerCase() ?? '';
      _assertTransition(fromStatus: fromStatus, toStatus: targetStatus);

      await txn.update(
        'trips',
        <String, Object?>{'status': targetStatus, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final eventId = _uuid.v4();
      await txn.insert('trip_events', <String, Object?>{
        'id': eventId,
        'trip_id': tripId,
        'actor_user_id': actorUserId,
        'from_status': fromStatus,
        'to_status': targetStatus,
        'metadata': metadataEncoded,
        'created_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final refreshedTripRows = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        limit: 1,
      );
      if (refreshedTripRows.isEmpty) {
        throw const DomainInvariantError(code: 'trip_not_found');
      }
      updatedTrip = _tripPayloadFromRow(
        Map<String, Object?>.from(refreshedTripRows.first),
      );

      final eventRows = await txn.query(
        'trip_events',
        where: 'id = ?',
        whereArgs: <Object>[eventId],
        limit: 1,
      );
      if (eventRows.isEmpty) {
        throw const DomainInvariantError(code: 'trip_event_not_found');
      }
      createdEvent = _eventPayloadFromRow(
        Map<String, Object?>.from(eventRows.first),
      );
    });

    return <String, Object?>{
      'trip': updatedTrip ?? const <String, Object?>{},
      'event': createdEvent ?? const <String, Object?>{},
    };
  }

  Future<Map<String, Object?>?> _findAccessibleTripRow({
    required String tripId,
    required String requesterUserId,
    required bool requesterIsAdmin,
  }) async {
    final rows = await _db.query(
      'trips',
      where: 'id = ?',
      whereArgs: <Object>[tripId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = Map<String, Object?>.from(rows.first);
    if (requesterIsAdmin) {
      return row;
    }
    final ownerUserId = (row['user_id'] as String?) ?? '';
    if (ownerUserId != requesterUserId) {
      return null;
    }
    return row;
  }

  Map<String, Object?> _tripPayloadFromRow(Map<String, Object?> row) {
    return <String, Object?>{
      'id': row['id'],
      'user_id': row['user_id'],
      'status': row['status'],
      'pickup': <String, Object?>{
        'lat': _asDouble(row['pickup_lat']),
        'lng': _asDouble(row['pickup_lng']),
        'address': _nullableTrim(row['pickup_address']),
      },
      'dropoff': <String, Object?>{
        'lat': _asDouble(row['dropoff_lat']),
        'lng': _asDouble(row['dropoff_lng']),
        'address': _nullableTrim(row['dropoff_address']),
      },
      'notes': _nullableTrim(row['notes']),
      'scheduled_at': _nullableTrim(row['scheduled_at']),
      'created_at': _nullableTrim(row['created_at']),
      'updated_at': _nullableTrim(row['updated_at']),
    };
  }

  Map<String, Object?> _eventPayloadFromRow(Map<String, Object?> row) {
    return <String, Object?>{
      'id': row['id'],
      'trip_id': row['trip_id'],
      'actor_user_id': row['actor_user_id'],
      'from_status': _nullableTrim(row['from_status']),
      'to_status': row['to_status'],
      'metadata': _decodeMetadata(row['metadata']),
      'created_at': _nullableTrim(row['created_at']),
    };
  }

  Map<Object?, Object?>? _asObjectMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<Object?, Object?>.from(value);
    }
    return null;
  }

  double _readCoordinate(
    Object? rawValue, {
    required String codeIfMissing,
    required String codeIfInvalid,
    required double min,
    required double max,
  }) {
    if (rawValue == null) {
      throw DomainInvariantError(code: codeIfMissing);
    }
    final value = _parseDouble(rawValue);
    if (value == null || value.isNaN || value.isInfinite) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    if (value < min || value > max) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    return value;
  }

  double? _parseDouble(Object? rawValue) {
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    if (rawValue is String) {
      return double.tryParse(rawValue.trim());
    }
    return null;
  }

  String? _optionalText(Object? value, {required String codeIfInvalid}) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _optionalIsoUtc(Object? value, {required String codeIfInvalid}) {
    final normalized = _optionalText(value, codeIfInvalid: codeIfInvalid);
    if (normalized == null) {
      return null;
    }
    final parsed = DateTime.tryParse(normalized)?.toUtc();
    if (parsed == null) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    return parsed.toIso8601String();
  }

  String _normalizeStatus(Object? statusRaw) {
    final normalized = (statusRaw as String?)?.trim().toLowerCase() ?? '';
    if (!knownStatuses.contains(normalized)) {
      throw const DomainInvariantError(code: 'invalid_trip_status');
    }
    return normalized;
  }

  String? _normalizeStatusFilter(String? statusRaw) {
    final normalized = statusRaw?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return _normalizeStatus(normalized);
  }

  void _assertTransition({
    required String fromStatus,
    required String toStatus,
  }) {
    final allowed = _allowedTransitions[fromStatus];
    if (allowed == null || !allowed.contains(toStatus)) {
      throw const DomainInvariantError(code: 'invalid_status_transition');
    }
  }

  String? _encodeMetadata(Object? metadata) {
    if (metadata == null) {
      return null;
    }
    try {
      return jsonEncode(metadata);
    } catch (_) {
      throw const DomainInvariantError(code: 'invalid_status_metadata');
    }
  }

  Object? _decodeMetadata(Object? raw) {
    final normalized = _nullableTrim(raw);
    if (normalized == null) {
      return null;
    }
    try {
      return jsonDecode(normalized);
    } catch (_) {
      return normalized;
    }
  }

  String? _nullableTrim(Object? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.toString().trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  double _asDouble(Object? value) {
    final parsed = _parseDouble(value);
    if (parsed == null) {
      return 0;
    }
    return parsed;
  }

  _DecodedCursor? _decodeCursor(String? cursorRaw) {
    final cursor = (cursorRaw ?? '').trim();
    if (cursor.isEmpty) {
      return null;
    }
    try {
      final normalized = _normalizeCursorBase64(cursor);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final separator = decoded.indexOf('|');
      if (separator <= 0 || separator >= decoded.length - 1) {
        throw const FormatException('invalid_cursor');
      }
      final createdAtIso = decoded.substring(0, separator).trim();
      final tripId = decoded.substring(separator + 1).trim();
      final createdAt = DateTime.tryParse(createdAtIso)?.toUtc();
      if (createdAt == null || tripId.isEmpty) {
        throw const FormatException('invalid_cursor');
      }
      return _DecodedCursor(
        createdAtIso: createdAt.toIso8601String(),
        tripId: tripId,
      );
    } catch (_) {
      throw const DomainInvariantError(code: 'invalid_pagination_cursor');
    }
  }

  String _encodeCursor(String createdAtIso, String tripId) {
    final payload = '$createdAtIso|$tripId';
    final encoded = base64UrlEncode(utf8.encode(payload));
    return encoded.replaceAll('=', '');
  }

  String _normalizeCursorBase64(String rawCursor) {
    final cursor = rawCursor.trim();
    final remainder = cursor.length % 4;
    if (remainder == 0) {
      return cursor;
    }
    final padding = List<String>.filled(4 - remainder, '=').join();
    return '$cursor$padding';
  }
}

class _DecodedCursor {
  const _DecodedCursor({required this.createdAtIso, required this.tripId});

  final String createdAtIso;
  final String tripId;
}
