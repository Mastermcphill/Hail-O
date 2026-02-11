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
}
