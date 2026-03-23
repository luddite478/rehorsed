import 'package:flutter/foundation.dart';
import '../models/pattern.dart';
import 'local_storage_service.dart';

/// Service for managing patterns locally
/// Stores patterns in patterns.json file
class LocalPatternService {
  static const String _patternsFile = 'patterns.json';

  /// Load all patterns from local storage
  static Future<List<Pattern>> loadPatterns() async {
    try {
      final jsonArray = await LocalStorageService.readJsonArrayFile(_patternsFile);
      final patterns = jsonArray.map((json) => Pattern.fromJson(json)).toList();
      debugPrint('📦 [PATTERNS] Loaded ${patterns.length} patterns');
      return patterns;
    } catch (e) {
      debugPrint('❌ [PATTERNS] Error loading patterns: $e');
      return [];
    }
  }

  /// Save pattern (update or insert)
  static Future<bool> savePattern(Pattern pattern) async {
    try {
      final patterns = await loadPatterns();
      
      // Update existing or add new
      final existingIndex = patterns.indexWhere((p) => p.id == pattern.id);
      if (existingIndex >= 0) {
        patterns[existingIndex] = pattern;
        debugPrint('📦 [PATTERNS] Updated pattern: ${pattern.id}');
      } else {
        patterns.add(pattern);
        debugPrint('📦 [PATTERNS] Added new pattern: ${pattern.id}');
      }
      
      // Save back to file
      final jsonArray = patterns.map((p) => p.toJson()).toList();
      return await LocalStorageService.writeJsonArrayFile(_patternsFile, jsonArray);
    } catch (e) {
      debugPrint('❌ [PATTERNS] Error saving pattern: $e');
      return false;
    }
  }

  /// Delete pattern and its checkpoints
  static Future<bool> deletePattern(String patternId) async {
    try {
      final patterns = await loadPatterns();
      
      // Remove pattern from list
      final initialLength = patterns.length;
      patterns.removeWhere((p) => p.id == patternId);
      
      if (patterns.length == initialLength) {
        debugPrint('⚠️ [PATTERNS] Pattern not found: $patternId');
        return false;
      }
      
      // Save updated list
      final jsonArray = patterns.map((p) => p.toJson()).toList();
      final success = await LocalStorageService.writeJsonArrayFile(_patternsFile, jsonArray);
      
      if (success) {
        // Delete checkpoints directory for this pattern
        await LocalStorageService.deleteDirectory('checkpoints/$patternId');
        debugPrint('📦 [PATTERNS] Deleted pattern: $patternId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [PATTERNS] Error deleting pattern: $e');
      return false;
    }
  }

  /// Get single pattern by ID
  static Future<Pattern?> getPattern(String patternId) async {
    try {
      final patterns = await loadPatterns();
      return patterns.firstWhere(
        (p) => p.id == patternId,
        orElse: () => throw Exception('Pattern not found'),
      );
    } catch (e) {
      debugPrint('❌ [PATTERNS] Error getting pattern $patternId: $e');
      return null;
    }
  }

  /// Clear all patterns (for testing/reset)
  static Future<bool> clearAll() async {
    try {
      await LocalStorageService.deleteFile(_patternsFile);
      await LocalStorageService.deleteDirectory('checkpoints');
      debugPrint('📦 [PATTERNS] Cleared all patterns');
      return true;
    } catch (e) {
      debugPrint('❌ [PATTERNS] Error clearing patterns: $e');
      return false;
    }
  }
}
