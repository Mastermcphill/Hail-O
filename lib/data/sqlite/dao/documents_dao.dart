import 'package:sqflite/sqflite.dart';

import '../../../domain/models/document_record.dart';
import '../table_names.dart';

class DocumentsDao {
  const DocumentsDao(this.db);

  final DatabaseExecutor db;

  Future<bool> hasCrossBorderDocument(String userId) async {
    final rows = await db.query(
      TableNames.documents,
      columns: <String>['id'],
      where: 'user_id = ? AND doc_type IN (?, ?)',
      whereArgs: <Object>[
        userId,
        DocumentType.passport.dbValue,
        DocumentType.ecowasId.dbValue,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasValidCrossBorderDocument(
    String userId, {
    DateTime? nowUtc,
    String? requiredCountry,
  }) async {
    return hasValidDocumentForTypes(
      userId,
      docTypes: <String>[
        DocumentType.passport.dbValue,
        DocumentType.ecowasId.dbValue,
      ],
      nowUtc: nowUtc,
      requiredCountry: requiredCountry,
      requireVerified: true,
      requireNotExpired: true,
    );
  }

  Future<bool> hasValidDocumentForTypes(
    String userId, {
    required List<String> docTypes,
    DateTime? nowUtc,
    String? requiredCountry,
    bool requireVerified = true,
    bool requireNotExpired = true,
  }) async {
    if (docTypes.isEmpty) {
      return false;
    }
    final nowIso = (nowUtc ?? DateTime.now().toUtc()).toUtc().toIso8601String();
    final where = StringBuffer('user_id = ?');
    final args = <Object>[userId];

    final docTypePlaceholders = List<String>.filled(
      docTypes.length,
      '?',
    ).join(', ');
    where.write(' AND doc_type IN ($docTypePlaceholders)');
    args.addAll(docTypes);

    if (requireVerified) {
      where.write(" AND (verified = 1 OR status = 'verified')");
    }
    if (requireNotExpired) {
      where.write(' AND (expires_at IS NULL OR expires_at > ?)');
      args.add(nowIso);
    }
    if (requiredCountry != null && requiredCountry.trim().isNotEmpty) {
      where.write(' AND (country IS NULL OR country = ?)');
      args.add(requiredCountry.trim().toUpperCase());
    }

    final rows = await db.query(
      TableNames.documents,
      columns: <String>['id'],
      where: where.toString(),
      whereArgs: args,
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
