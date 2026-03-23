import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves stored filesystem paths for local audio (library, recordings).
///
/// Handles `file://` URLs, iOS `/var` vs `/private/var`, and stale absolute
/// paths when the file still exists under [Documents/recordings] or imported
/// samples (basename match).
class LocalAudioPath {
  LocalAudioPath._();

  /// Trim and convert `file:` URIs to a filesystem path.
  static String normalize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    if (t.startsWith('file:')) {
      try {
        return Uri.parse(t).toFilePath();
      } catch (_) {
        return t;
      }
    }
    return t;
  }

  static Iterable<String> _pathVariants(String filesystemPath) sync* {
    yield filesystemPath;
    // iOS often exposes the same tree as /var/... and /private/var/...
    if (filesystemPath.startsWith('/var/') &&
        !filesystemPath.startsWith('/private/')) {
      yield '/private$filesystemPath';
    }
    if (filesystemPath.startsWith('/private/var/')) {
      yield filesystemPath.replaceFirst('/private', '');
    }
  }

  /// Returns a path that exists on disk, or null.
  static Future<String?> resolve(String raw) async {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return null;

    for (final candidate in _pathVariants(normalized)) {
      try {
        final file = File(candidate);
        if (await file.exists()) return file.path;
      } catch (_) {}
    }

    return _relocateByBasename(p.basename(normalized));
  }

  static Future<String?> _relocateByBasename(String basename) async {
    if (basename.isEmpty) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = docs.path;

      final directCandidates = [
        p.join(root, 'recordings', basename),
        p.join(root, 'audio_cache', basename),
      ];
      for (final path in directCandidates) {
        final f = File(path);
        if (await f.exists()) return f.path;
      }

      final customRoot = Directory(p.join(root, 'library_samples', 'custom'));
      if (await customRoot.exists()) {
        await for (final entity in customRoot.list(recursive: true)) {
          if (entity is File && p.basename(entity.path) == basename) {
            return entity.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
