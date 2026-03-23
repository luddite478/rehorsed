import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../utils/local_audio_path.dart';

/// Service for managing local audio files with LRU eviction
/// 
/// Features:
/// - Manages locally stored audio files
/// - Size-based eviction (default 1GB limit)
/// - LRU eviction (least recently used files deleted first)
/// - Tracks access times for intelligent eviction
class AudioCacheService {
  static final Map<String, String> _idToLocalPathCache = {};
  
  // Cache size limit (1GB default)
  static const int maxCacheSizeBytes = 1 * 1024 * 1024 * 1024;
  static const String _metadataFileName = 'audio_metadata.json';

  /// Get cache directory for audio files
  static Future<String> getCacheDirectory() async {
    final appName = dotenv.env['APP_NAME'] ?? 'app';
    String baseDir;
    
    if (Platform.isAndroid) {
      baseDir = '/storage/emulated/0/Download/${appName}_data';
    } else if (Platform.isIOS) {
      // Use Documents directory for persistent storage on iOS
      final appDocDir = await getApplicationDocumentsDirectory();
      baseDir = appDocDir.path;
    } else if (Platform.isMacOS) {
      baseDir = '${Platform.environment['HOME']}/Documents/$appName';
    } else if (Platform.isWindows) {
      baseDir = '${Platform.environment['USERPROFILE']}\\Documents\\$appName';
    } else {
      baseDir = path.join(Directory.systemTemp.path, appName);
    }
    
    final cacheDir = path.join(baseDir, 'audio_cache');
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Generate local file path for an audio ID
  static Future<String> getLocalPathForId(String id, String extension) async {
    final cacheDir = await getCacheDirectory();
    
    // Ensure extension starts with a dot
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final filename = '$id$ext';
    
    return path.join(cacheDir, filename);
  }

  /// Check if audio file exists at path
  static Future<bool> fileExists(String localPath) async {
    try {
      final file = File(localPath);
      return await file.exists();
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error checking file: $e');
      return false;
    }
  }

  /// Get playable path for local file
  /// Returns the path if file exists, null otherwise
  static Future<String?> getPlayablePath(String localPath) async {
    try {
      final resolved = await LocalAudioPath.resolve(localPath);
      if (resolved == null) {
        debugPrint('⚠️ [AUDIO_CACHE] File not found: $localPath');
        return null;
      }
      await _updateAudioAccessTime(resolved);
      if (resolved != localPath) {
        debugPrint('🎵 [AUDIO_CACHE] Resolved stale path → $resolved');
      } else {
        debugPrint('🎵 [AUDIO_CACHE] Using local file: $resolved');
      }
      return resolved;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error getting playable path: $e');
      return null;
    }
  }

  /// Store audio file in cache (copy to cache directory)
  static Future<String?> storeAudioFile(
    String sourcePath,
    String id,
    String format,
  ) async {
    try {
      // Check cache size before storing
      final cacheSize = await getCacheSize();
      if (cacheSize >= maxCacheSizeBytes) {
        debugPrint('⚠️ [AUDIO_CACHE] Cache full, evicting old files');
        await _evictLeastRecentlyUsedAudio();
      }

      final destPath = await getLocalPathForId(id, format);
      final sourceFile = File(sourcePath);
      
      if (!await sourceFile.exists()) {
        debugPrint('❌ [AUDIO_CACHE] Source file not found: $sourcePath');
        return null;
      }

      // Copy file to cache directory
      await sourceFile.copy(destPath);
      
      _idToLocalPathCache[id] = destPath;
      await _updateAudioAccessTime(destPath);
      
      debugPrint('✅ [AUDIO_CACHE] Stored audio: $destPath');
      return destPath;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error storing audio: $e');
      return null;
    }
  }

  /// Delete audio file from cache
  static Future<bool> deleteAudioFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
        
        // Remove from metadata
        final metadata = await _loadAudioMetadata();
        metadata.remove(localPath);
        await _saveAudioMetadata(metadata);
        
        // Remove from memory cache
        _idToLocalPathCache.removeWhere((key, value) => value == localPath);
        
        debugPrint('🗑️ [AUDIO_CACHE] Deleted: $localPath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error deleting file: $e');
      return false;
    }
  }

  /// Clear entire cache
  static Future<void> clearCache() async {
    try {
      final cacheDir = await getCacheDirectory();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _idToLocalPathCache.clear();
      debugPrint('🗑️ [AUDIO_CACHE] Cache cleared');
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error clearing cache: $e');
    }
  }

  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await getCacheDirectory();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && !entity.path.endsWith(_metadataFileName)) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error getting cache size: $e');
      return 0;
    }
  }

  /// Format cache size for display
  static String formatCacheSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ============================================================================
  // LRU Eviction Methods
  // ============================================================================

  /// Get path to metadata file
  static Future<File> _getMetadataFile() async {
    final cacheDir = await getCacheDirectory();
    return File(path.join(cacheDir, _metadataFileName));
  }

  /// Load audio metadata (access times, etc.)
  static Future<Map<String, dynamic>> _loadAudioMetadata() async {
    try {
      final file = await _getMetadataFile();
      if (!await file.exists()) {
        return {};
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error loading metadata: $e');
      return {};
    }
  }

  /// Save audio metadata
  static Future<void> _saveAudioMetadata(Map<String, dynamic> metadata) async {
    try {
      final file = await _getMetadataFile();
      await file.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error saving metadata: $e');
    }
  }

  /// Update access time for a file (for LRU tracking)
  static Future<void> _updateAudioAccessTime(String filePath) async {
    try {
      final metadata = await _loadAudioMetadata();
      
      metadata[filePath] = {
        'last_accessed_at': DateTime.now().toIso8601String(),
        'access_count': (metadata[filePath]?['access_count'] ?? 0) + 1,
      };

      await _saveAudioMetadata(metadata);
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error updating access time: $e');
    }
  }

  /// Evict least recently used audio files to free up space
  static Future<void> _evictLeastRecentlyUsedAudio() async {
    try {
      final metadata = await _loadAudioMetadata();
      final cacheDir = await getCacheDirectory();
      final dir = Directory(cacheDir);

      // Get all audio files with access times
      final List<_AudioFileMeta> files = [];
      await for (final entity in dir.list()) {
        if (entity is File && 
            !entity.path.endsWith(_metadataFileName) &&
            (entity.path.endsWith('.mp3') || 
             entity.path.endsWith('.wav') ||
             entity.path.endsWith('.m4a'))) {
          final filePath = entity.path;
          final lastAccessed = metadata[filePath]?['last_accessed_at'] != null
              ? DateTime.parse(metadata[filePath]!['last_accessed_at'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0);

          final size = await entity.length();
          files.add(_AudioFileMeta(
            file: entity,
            filePath: filePath,
            lastAccessed: lastAccessed,
            size: size,
          ));
        }
      }

      // Sort by last accessed (oldest first)
      files.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      // Delete oldest files until under limit (target 80% of limit)
      final targetSize = (maxCacheSizeBytes * 0.8).toInt();
      int currentSize = await getCacheSize();
      int deletedCount = 0;

      for (var fileMeta in files) {
        if (currentSize <= targetSize) break;

        await fileMeta.file.delete();
        metadata.remove(fileMeta.filePath);
        _idToLocalPathCache.removeWhere((key, value) => value == fileMeta.filePath);
        currentSize -= fileMeta.size;
        deletedCount++;

        debugPrint('🗑️ [AUDIO_CACHE] Evicted: ${path.basename(fileMeta.file.path)}');
      }

      // Save updated metadata
      await _saveAudioMetadata(metadata);

      debugPrint('✅ [AUDIO_CACHE] Evicted $deletedCount files, cache now ${formatCacheSize(currentSize)}');
    } catch (e) {
      debugPrint('❌ [AUDIO_CACHE] Error during eviction: $e');
    }
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final size = await getCacheSize();
      final metadata = await _loadAudioMetadata();
      final fileCount = metadata.length;

      return {
        'file_count': fileCount,
        'size_bytes': size,
        'size_formatted': formatCacheSize(size),
        'limit_bytes': maxCacheSizeBytes,
        'limit_formatted': formatCacheSize(maxCacheSizeBytes),
        'usage_percent': ((size / maxCacheSizeBytes) * 100).toStringAsFixed(1),
      };
    } catch (e) {
      return {
        'file_count': 0,
        'size_bytes': 0,
        'size_formatted': '0 B',
        'limit_bytes': maxCacheSizeBytes,
        'limit_formatted': formatCacheSize(maxCacheSizeBytes),
        'usage_percent': '0.0',
      };
    }
  }
}

/// Internal class to hold audio file metadata for LRU eviction
class _AudioFileMeta {
  final File file;
  final String filePath;
  final DateTime lastAccessed;
  final int size;

  _AudioFileMeta({
    required this.file,
    required this.filePath,
    required this.lastAccessed,
    required this.size,
  });
}
