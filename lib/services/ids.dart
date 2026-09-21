import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stable UUID v4 for new entities (holdings, sells, watch items).
String newEntityId() => _uuid.v4();

/// Prefer existing non-empty id; otherwise mint a new UUID.
String ensureEntityId(String? id) {
  final t = id?.trim() ?? '';
  return t.isEmpty ? newEntityId() : t;
}
