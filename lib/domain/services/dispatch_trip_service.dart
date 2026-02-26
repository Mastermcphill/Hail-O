import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../errors/domain_errors.dart';

class DispatchNotFoundError implements Exception {
  const DispatchNotFoundError({required this.code, required this.message});

  final String code;
  final String message;
}

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

    final response = <String, Object?>{'trips': trips};
    if (nextCursor case final value?) {
      response['next_cursor'] = value;
    }
    return response;
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

  Future<Map<String, Object?>> assignDriver({
    required String tripId,
    required String actorUserId,
    required bool actorIsAdmin,
    required Map<String, Object?> payload,
  }) async {
    final driverId = _requiredText(
      payload['driver_id'],
      codeIfMissing: 'driver_id_required',
      codeIfInvalid: 'invalid_driver_id',
    );
    final nowIso = _nowUtc().toUtc().toIso8601String();

    Map<String, Object?>? updatedTrip;
    Map<String, Object?>? createdAssignment;

    await _db.transaction((txn) async {
      final tripRows = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        limit: 1,
      );
      if (tripRows.isEmpty) {
        throw const DispatchNotFoundError(
          code: 'trip_not_found',
          message: 'Trip not found',
        );
      }
      final trip = Map<String, Object?>.from(tripRows.first);
      final tripOwnerUserId = (trip['user_id'] as String?) ?? '';
      if (!actorIsAdmin && tripOwnerUserId != actorUserId) {
        throw const DispatchNotFoundError(
          code: 'trip_not_found',
          message: 'Trip not found',
        );
      }

      await _assertValidDriver(txn, driverId: driverId);

      final assignmentRows = await txn.query(
        'trip_assignments',
        where: 'trip_id = ?',
        whereArgs: <Object>[tripId],
        limit: 1,
      );
      if (assignmentRows.isNotEmpty) {
        throw const DomainInvariantError(code: 'trip_already_assigned');
      }

      final currentStatus =
          (trip['status'] as String?)?.trim().toLowerCase() ?? '';
      if (currentStatus != 'created' && currentStatus != 'searching') {
        throw const DomainInvariantError(
          code: 'assignment_not_allowed_from_status',
        );
      }

      var transitionFrom = currentStatus;
      if (currentStatus == 'created') {
        await txn.update(
          'trips',
          <String, Object?>{'status': 'searching', 'updated_at': nowIso},
          where: 'id = ?',
          whereArgs: <Object>[tripId],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await _insertTripEvent(
          txn,
          tripId: tripId,
          actorUserId: actorUserId,
          fromStatus: 'created',
          toStatus: 'searching',
          metadata: _encodeMetadata(const <String, Object?>{
            'reason': 'assignment_flow',
          }),
          createdAtIso: nowIso,
        );
        transitionFrom = 'searching';
      }

      final assignmentId = _uuid.v4();
      await txn.insert('trip_assignments', <String, Object?>{
        'id': assignmentId,
        'trip_id': tripId,
        'driver_id': driverId,
        'status': 'assigned',
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.update(
        'trips',
        <String, Object?>{'status': 'assigned', 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _insertTripEvent(
        txn,
        tripId: tripId,
        actorUserId: actorUserId,
        fromStatus: transitionFrom,
        toStatus: 'assigned',
        metadata: _encodeMetadata(<String, Object?>{
          'assignment_id': assignmentId,
          'driver_id': driverId,
        }),
        createdAtIso: nowIso,
      );

      final refreshedTripRows = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: <Object>[tripId],
        limit: 1,
      );
      if (refreshedTripRows.isEmpty) {
        throw const DispatchNotFoundError(
          code: 'trip_not_found',
          message: 'Trip not found',
        );
      }
      updatedTrip = _tripPayloadFromRow(
        Map<String, Object?>.from(refreshedTripRows.first),
      );

      final createdAssignmentRows = await txn.query(
        'trip_assignments',
        where: 'id = ?',
        whereArgs: <Object>[assignmentId],
        limit: 1,
      );
      if (createdAssignmentRows.isEmpty) {
        throw const DomainInvariantError(code: 'assignment_persist_failed');
      }
      createdAssignment = _assignmentPayloadFromRow(
        Map<String, Object?>.from(createdAssignmentRows.first),
      );
    });

    return <String, Object?>{
      'trip': updatedTrip ?? const <String, Object?>{},
      'assignment': createdAssignment ?? const <String, Object?>{},
    };
  }

  Future<Map<String, Object?>> listNearbyDrivers({required int limit}) async {
    final hasDriverProfiles = await _tableExists(_db, 'driver_profiles');
    if (!hasDriverProfiles) {
      return const <String, Object?>{'drivers': <Map<String, Object?>>[]};
    }
    final rows = await _db.rawQuery(
      '''
      SELECT
        dp.driver_id,
        dp.status,
        dp.safety_score,
        dp.updated_at,
        u.display_name,
        u.star_rating
      FROM driver_profiles dp
      LEFT JOIN users u
      ON u.id = dp.driver_id
      ORDER BY COALESCE(u.star_rating, 0) DESC, dp.updated_at DESC
      LIMIT ?
      ''',
      <Object>[limit],
    );
    final drivers = rows
        .map(
          (row) => _nearbyDriverPayloadFromRow(Map<String, Object?>.from(row)),
        )
        .toList(growable: false);
    return <String, Object?>{'drivers': drivers};
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

  Map<String, Object?> _assignmentPayloadFromRow(Map<String, Object?> row) {
    return <String, Object?>{
      'id': row['id'],
      'trip_id': row['trip_id'],
      'driver_id': row['driver_id'],
      'status': row['status'],
      'created_at': _nullableTrim(row['created_at']),
      'updated_at': _nullableTrim(row['updated_at']),
    };
  }

  Map<String, Object?> _nearbyDriverPayloadFromRow(Map<String, Object?> row) {
    return <String, Object?>{
      'driver_id': row['driver_id'],
      'display_name': _nullableTrim(row['display_name']),
      'status': _nullableTrim(row['status']) ?? 'active',
      'safety_score': (row['safety_score'] as num?)?.toInt() ?? 0,
      'star_rating': (row['star_rating'] as num?)?.toDouble() ?? 0,
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

  String _requiredText(
    Object? value, {
    required String codeIfMissing,
    required String codeIfInvalid,
  }) {
    if (value == null) {
      throw DomainInvariantError(code: codeIfMissing);
    }
    if (value is! String) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw DomainInvariantError(code: codeIfMissing);
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

  Future<void> _insertTripEvent(
    DatabaseExecutor txn, {
    required String tripId,
    required String actorUserId,
    required String? fromStatus,
    required String toStatus,
    required String? metadata,
    required String createdAtIso,
  }) {
    return txn.insert('trip_events', <String, Object?>{
      'id': _uuid.v4(),
      'trip_id': tripId,
      'actor_user_id': actorUserId,
      'from_status': fromStatus,
      'to_status': toStatus,
      'metadata': metadata,
      'created_at': createdAtIso,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> _assertValidDriver(
    DatabaseExecutor executor, {
    required String driverId,
  }) async {
    final userRows = await executor.query(
      'users',
      columns: <String>['id', 'role'],
      where: 'id = ?',
      whereArgs: <Object>[driverId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      throw const DispatchNotFoundError(
        code: 'driver_not_found',
        message: 'Driver not found',
      );
    }

    final hasUserRolesTable = await _tableExists(executor, 'user_roles');
    if (hasUserRolesTable) {
      final roleRows = await executor.query(
        'user_roles',
        columns: <String>['role'],
        where: 'user_id = ? AND role = ?',
        whereArgs: <Object>[driverId, 'driver'],
        limit: 1,
      );
      if (roleRows.isNotEmpty) {
        return;
      }
      throw const DispatchNotFoundError(
        code: 'driver_not_found',
        message: 'Driver not found',
      );
    }

    final userRole =
        (userRows.first['role'] as String?)?.trim().toLowerCase() ?? '';
    if (userRole == 'driver') {
      return;
    }

    final hasDriverProfilesTable = await _tableExists(
      executor,
      'driver_profiles',
    );
    if (hasDriverProfilesTable) {
      final profileRows = await executor.query(
        'driver_profiles',
        columns: <String>['driver_id'],
        where: 'driver_id = ?',
        whereArgs: <Object>[driverId],
        limit: 1,
      );
      if (profileRows.isNotEmpty) {
        return;
      }
    }

    throw const DispatchNotFoundError(
      code: 'driver_not_found',
      message: 'Driver not found',
    );
  }

  Future<bool> _tableExists(DatabaseExecutor executor, String tableName) async {
    final rows = await executor.rawQuery(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      <Object>['table', tableName],
    );
    return rows.isNotEmpty;
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
