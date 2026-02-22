import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

String newRequestId() => _uuid.v4();

String newIdempotencyKey() => _uuid.v4();
