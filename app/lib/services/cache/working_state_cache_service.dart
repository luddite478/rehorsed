import 'package:flutter/foundation.dart';
import 'local_cache_service.dart';

/// Manages working state (auto-saved drafts) for patterns
/// 
/// Strategy:
/// - One working state per pattern (latest auto-saved state)
/// - Independent from saved checkpoints
/// - Loaded first in hierarchy (cache-first for unsaved work)
/// - Persists across app restarts
/// - Cleared optionally when user saves a checkpoint
/// 
/// Use cases:
/// - Auto-save user edits every 5 seconds (offline-only)
/// - Recover work after app crash
/// - Switch between patterns without losing work
/// - Local persistence only (no server sync)
class WorkingStateCacheService {
  static const String _workingStatesDir = 'working_states';

  /// Get the file path for a pattern's working state
  static String _getFilePath(String patternId) => '$_workingStatesDir/$patternId.json';

  /// Save working state for a pattern (auto-save draft)
  /// 
  /// This is called automatically by the auto-save manager when:
  /// - User makes changes to table, playback, or sample bank
  /// - 5 seconds pass without additional changes (debounced)
  /// 
  /// Returns true if save was successful
  static Future<bool> saveWorkingState(
    String patternId,
    Map<String, dynamic> snapshot,
  ) async {
    try {
      final data = {
        'version': 1,
        'pattern_id': patternId,
        'saved_at': DateTime.now().toIso8601String(),
        'snapshot': snapshot,
      };

      final success = await LocalCacheService.writeJson(_getFilePath(patternId), data);
      
      if (success) {
        debugPrint('💾 [WORKING_STATE] Saved working state for pattern $patternId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error saving working state: $e');
      return false;
    }
  }

  /// Load working state for a pattern
  /// 
  /// Returns the snapshot if working state exists, null otherwise.
  /// This is checked FIRST in the loading hierarchy, before checkpoints.
  static Future<Map<String, dynamic>?> loadWorkingState(String patternId) async {
    try {
      final data = await LocalCacheService.readJson(_getFilePath(patternId));
      if (data == null) {
        return null;
      }

      final snapshot = data['snapshot'] as Map<String, dynamic>?;
      
      if (snapshot != null && snapshot.isNotEmpty) {
        final savedAt = data['saved_at'] as String?;
        debugPrint('📝 [WORKING_STATE] Loaded working state for pattern $patternId (saved: $savedAt)');
      }
      
      return snapshot;
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error loading working state: $e');
      return null;
    }
  }

  /// Check if working state exists for a pattern
  static Future<bool> hasWorkingState(String patternId) async {
    return await LocalCacheService.fileExists(_getFilePath(patternId));
  }

  /// Get working state timestamp (when it was last saved)
  /// 
  /// Useful for:
  /// - Showing "Last auto-saved: X minutes ago" in UI
  /// - Comparing with checkpoint timestamps
  /// - Debugging/diagnostics
  static Future<DateTime?> getWorkingStateTimestamp(String patternId) async {
    try {
      final data = await LocalCacheService.readJson(_getFilePath(patternId));
      if (data == null) return null;

      final savedAt = data['saved_at'] as String?;
      if (savedAt != null) {
        return DateTime.parse(savedAt);
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error getting timestamp: $e');
      return null;
    }
  }

  /// Clear working state for a pattern
  /// 
  /// Called when:
  /// - User explicitly saves a checkpoint (optional, based on policy)
  /// - User wants to discard local changes
  /// - Cleaning up old patterns
  static Future<void> clearWorkingState(String patternId) async {
    try {
      final deleted = await LocalCacheService.deleteFile(_getFilePath(patternId));
      if (deleted) {
        debugPrint('🗑️ [WORKING_STATE] Cleared working state for pattern $patternId');
      }
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error clearing working state: $e');
    }
  }

  /// Clear all working states (for cleanup/reset)
  static Future<void> clearAllWorkingStates() async {
    try {
      final dir = await LocalCacheService.getCacheDirectory(_workingStatesDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      debugPrint('✅ [WORKING_STATE] All working states cleared');
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error clearing all working states: $e');
    }
  }

  /// Get statistics about working states
  /// 
  /// Useful for:
  /// - Cache management UI
  /// - Storage diagnostics
  /// - Cleanup decisions
  static Future<Map<String, dynamic>> getWorkingStateStats() async {
    try {
      final files = await LocalCacheService.listFiles(_workingStatesDir);
      final size = await LocalCacheService.getDirectorySize(_workingStatesDir);

      return {
        'count': files.length,
        'size_bytes': size,
        'size_formatted': LocalCacheService.formatBytes(size),
      };
    } catch (e) {
      return {
        'count': 0,
        'size_bytes': 0,
        'size_formatted': '0 B',
      };
    }
  }

  /// Get list of all patterns with working states
  /// 
  /// Useful for:
  /// - Showing which patterns have unsaved changes
  /// - Bulk cleanup operations
  static Future<List<String>> getPatternsWithWorkingStates() async {
    try {
      final files = await LocalCacheService.listFiles(_workingStatesDir);
      
      return files
          .where((f) => f.path.endsWith('.json'))
          .map((f) {
            // Extract pattern ID from filename (remove .json extension)
            final filename = f.path.split('/').last;
            return filename.replaceAll('.json', '');
          })
          .toList();
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error getting pattern list: $e');
      return [];
    }
  }
}

