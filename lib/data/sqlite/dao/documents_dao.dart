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
    final nowIso = (nowUtc ?? DateTime.now().toUtc()).toUtc().toIso8601String();
    final where = StringBuffer(
      'user_id = ? '
      'AND doc_type IN (?, ?) '
      "AND (verified = 1 OR status = 'verified') "
      'AND (expires_at IS NULL OR expires_at > ?)',
    );
    final args = <Object>[
      userId,
      DocumentType.passport.dbValue,
      DocumentType.ecowasId.dbValue,
      nowIso,
    ];
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
