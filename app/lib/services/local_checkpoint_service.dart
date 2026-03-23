import 'package:flutter/foundation.dart';
import '../models/checkpoint.dart';
import '../utils/local_audio_path.dart';
import 'local_storage_service.dart';

/// Service for managing checkpoints locally
/// Stores checkpoint snapshots in checkpoints/{patternId}/{checkpointId}.json
class LocalCheckpointService {
  /// Load all checkpoints for a pattern
  static Future<List<Checkpoint>> loadCheckpoints(String patternId) async {
    try {
      final files = await LocalStorageService.listFiles('checkpoints/$patternId');
      
      final checkpoints = <Checkpoint>[];
      for (final filename in files) {
        if (filename.endsWith('.json')) {
          final json = await LocalStorageService.readJsonFile(
            'checkpoints/$patternId/$filename',
          );
          if (json != null) {
            checkpoints.add(Checkpoint.fromJson(json));
          }
        }
      }
      
      // Sort by created date (newest first)
      checkpoints.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final resolved = await Future.wait(
        checkpoints.map((c) => c.audioFilePath != null
            ? LocalAudioPath.resolve(c.audioFilePath!)
            : Future.value(null)),
      );
      final repaired = <Checkpoint>[];
      final saves = <Future<bool>>[];
      for (var i = 0; i < checkpoints.length; i++) {
        final c = checkpoints[i];
        final r = resolved[i];
        if (r != null && r != c.audioFilePath) {
          final fixed = c.copyWith(audioFilePath: r);
          saves.add(saveCheckpoint(fixed));
          repaired.add(fixed);
          debugPrint('💾 [CHECKPOINTS] Repaired audio path for checkpoint ${c.id}');
        } else {
          repaired.add(c);
        }
      }
      if (saves.isNotEmpty) await Future.wait(saves);

      debugPrint('💾 [CHECKPOINTS] Loaded ${repaired.length} checkpoints for pattern $patternId');
      return repaired;
    } catch (e) {
      debugPrint('❌ [CHECKPOINTS] Error loading checkpoints: $e');
      return [];
    }
  }

  /// Save checkpoint
  static Future<bool> saveCheckpoint(Checkpoint checkpoint) async {
    try {
      final path = 'checkpoints/${checkpoint.patternId}/${checkpoint.id}.json';
      final success = await LocalStorageService.writeJsonFile(path, checkpoint.toJson());
      
      if (success) {
        debugPrint('💾 [CHECKPOINTS] Saved checkpoint: ${checkpoint.id}');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [CHECKPOINTS] Error saving checkpoint: $e');
      return false;
    }
  }

  /// Delete checkpoint
  static Future<bool> deleteCheckpoint(String patternId, String checkpointId) async {
    try {
      final path = 'checkpoints/$patternId/$checkpointId.json';
      final success = await LocalStorageService.deleteFile(path);
      
      if (success) {
        debugPrint('💾 [CHECKPOINTS] Deleted checkpoint: $checkpointId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [CHECKPOINTS] Error deleting checkpoint: $e');
      return false;
    }
  }

  /// Get single checkpoint by ID
  static Future<Checkpoint?> getCheckpoint(String patternId, String checkpointId) async {
    try {
      final path = 'checkpoints/$patternId/$checkpointId.json';
      final json = await LocalStorageService.readJsonFile(path);
      
      if (json == null) {
        return null;
      }
      
      return Checkpoint.fromJson(json);
    } catch (e) {
      debugPrint('❌ [CHECKPOINTS] Error getting checkpoint $checkpointId: $e');
      return null;
    }
  }

  /// Delete all checkpoints for a pattern
  static Future<bool> deletePatternCheckpoints(String patternId) async {
    try {
      final success = await LocalStorageService.deleteDirectory('checkpoints/$patternId');
      
      if (success) {
        debugPrint('💾 [CHECKPOINTS] Deleted all checkpoints for pattern: $patternId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [CHECKPOINTS] Error deleting pattern checkpoints: $e');
      return false;
    }
  }
}
