import 'package:uuid/uuid.dart';

/// Utility for generating UUIDs for patterns, checkpoints, and library items
class IdGenerator {
  static const _uuid = Uuid();
  
  /// Generate a new UUID v4
  static String generate() {
    return _uuid.v4();
  }
}
