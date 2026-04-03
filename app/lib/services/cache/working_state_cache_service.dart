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
/// Result of [WorkingStateCacheService.loadWorkingStateEnvelope].
class WorkingStateEnvelope {
  /// When this draft was written (from file `saved_at`), if parseable.
  final DateTime? savedAt;
  final Map<String, dynamic> snapshot;

  const WorkingStateEnvelope({
    required this.savedAt,
    required this.snapshot,
  });
}

class WorkingStateCacheService {
  // New canonical location for latest pattern state.
  static const String _latestStatesDir = 'latest_states';
  // Legacy location used by the old draft system (kept for one-time migration).
  static const String _legacyWorkingStatesDir = 'working_states';

  /// Get the file path for a pattern's latest state.
  static String _getFilePath(String patternId) => '$_latestStatesDir/$patternId.json';

  /// Legacy path used before latest-state unification.
  static String _getLegacyFilePath(String patternId) =>
      '$_legacyWorkingStatesDir/$patternId.json';

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
        debugPrint('💾 [WORKING_STATE] Saved latest state for pattern $patternId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error saving working state: $e');
      return false;
    }
  }

  /// Load latest working state for a pattern
  ///
  /// Returns the snapshot if working state exists, null otherwise.
  static Future<Map<String, dynamic>?> loadWorkingState(String patternId) async {
    final envelope = await loadWorkingStateEnvelope(patternId);
    return envelope?.snapshot;
  }

  /// Load latest state envelope with [savedAt].
  ///
  /// Returns null if the file is missing or has no non-empty snapshot.
  static Future<WorkingStateEnvelope?> loadWorkingStateEnvelope(
      String patternId) async {
    try {
      final data = await _readLatestOrMigrateLegacy(patternId);
      if (data == null) return null;

      final snapshot = data['snapshot'] as Map<String, dynamic>?;
      if (snapshot == null || snapshot.isEmpty) {
        return null;
      }

      DateTime? savedAt;
      final savedAtStr = data['saved_at'] as String?;
      if (savedAtStr != null) {
        savedAt = DateTime.tryParse(savedAtStr);
      }

      debugPrint(
          '📝 [WORKING_STATE] Loaded latest state for pattern $patternId (saved: $savedAtStr)');

      return WorkingStateEnvelope(savedAt: savedAt, snapshot: snapshot);
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error loading working state: $e');
      return null;
    }
  }

  /// Read latest-state envelope, migrating legacy working-state on first load.
  static Future<Map<String, dynamic>?> _readLatestOrMigrateLegacy(
      String patternId) async {
    final latest = await LocalCacheService.readJson(_getFilePath(patternId));
    if (latest != null) return latest;

    final legacy = await LocalCacheService.readJson(_getLegacyFilePath(patternId));
    if (legacy == null) return null;

    final migrated = await LocalCacheService.writeJson(_getFilePath(patternId), legacy);
    if (migrated) {
      await LocalCacheService.deleteFile(_getLegacyFilePath(patternId));
      debugPrint('🔁 [WORKING_STATE] Migrated legacy working state for $patternId');
    }
    return legacy;
  }

  /// Check if working state exists for a pattern
  static Future<bool> hasWorkingState(String patternId) async {
    final hasLatest = await LocalCacheService.fileExists(_getFilePath(patternId));
    if (hasLatest) return true;
    return await LocalCacheService.fileExists(_getLegacyFilePath(patternId));
  }

  /// Get working state timestamp (when it was last saved)
  /// 
  /// Useful for:
  /// - Showing "Last auto-saved: X minutes ago" in UI
  /// - Comparing with checkpoint timestamps
  /// - Debugging/diagnostics
  static Future<DateTime?> getWorkingStateTimestamp(String patternId) async {
    try {
      final data = await _readLatestOrMigrateLegacy(patternId);
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
      final deletedLatest = await LocalCacheService.deleteFile(_getFilePath(patternId));
      final deletedLegacy =
          await LocalCacheService.deleteFile(_getLegacyFilePath(patternId));
      if (deletedLatest || deletedLegacy) {
        debugPrint('🗑️ [WORKING_STATE] Cleared latest state for pattern $patternId');
      }
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error clearing working state: $e');
    }
  }

  /// Clear all working states (for cleanup/reset)
  static Future<void> clearAllWorkingStates() async {
    try {
      final latestDir = await LocalCacheService.getCacheDirectory(_latestStatesDir);
      if (await latestDir.exists()) {
        await latestDir.delete(recursive: true);
      }
      final legacyDir =
          await LocalCacheService.getCacheDirectory(_legacyWorkingStatesDir);
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
      debugPrint('✅ [WORKING_STATE] All latest states cleared');
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
      final files = await LocalCacheService.listFiles(_latestStatesDir);
      final size = await LocalCacheService.getDirectorySize(_latestStatesDir);

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
      final latestFiles = await LocalCacheService.listFiles(_latestStatesDir);
      final legacyFiles =
          await LocalCacheService.listFiles(_legacyWorkingStatesDir);
      final all = <String>{};

      for (final f in [...latestFiles, ...legacyFiles]) {
        if (!f.path.endsWith('.json')) continue;
        final filename = f.path.split('/').last;
        all.add(filename.replaceAll('.json', ''));
      }

      return all.toList()
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('❌ [WORKING_STATE] Error getting pattern list: $e');
      return [];
    }
  }
}

