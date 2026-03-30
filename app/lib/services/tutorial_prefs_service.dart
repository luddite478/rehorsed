import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'local_storage_service.dart';

/// Persistent storage for tutorial onboarding preferences.
class TutorialPrefsService {
  static const String _prefsFile = 'tutorial_prefs.json';
  static Future<void> _pendingWrite = Future<void>.value();

  static Future<bool> getBool(
    String key, {
    bool defaultValue = false,
  }) async {
    final data = await LocalStorageService.readJsonFile(_prefsFile);
    final existing = data?[key];
    if (existing is bool) return existing;

    // One-time fallback for installs that previously stored tutorial prefs
    // via ReliableStorage. If found, migrate into tutorial_prefs.json.
    final legacyValue = await _readLegacyBool(key);
    if (legacyValue != null) {
      await setBool(key, legacyValue);
      return legacyValue;
    }

    return defaultValue;
  }

  static Future<void> setBool(String key, bool value) async {
    await _serializeWrite(() async {
      final data = await _readPrefsOrEmpty();
      data[key] = value;
      await LocalStorageService.writeJsonFile(_prefsFile, data);
    });
  }

  static Future<String> getString(
    String key, {
    String defaultValue = '',
  }) async {
    final data = await LocalStorageService.readJsonFile(_prefsFile);
    final existing = data?[key];
    if (existing is String) return existing;
    return defaultValue;
  }

  static Future<void> setString(String key, String value) async {
    await _serializeWrite(() async {
      final data = await _readPrefsOrEmpty();
      data[key] = value;
      await LocalStorageService.writeJsonFile(_prefsFile, data);
    });
  }

  static Future<void> remove(String key) async {
    await _serializeWrite(() async {
      final data = await LocalStorageService.readJsonFile(_prefsFile);
      if (data == null || !data.containsKey(key)) return;
      data.remove(key);
      if (data.isEmpty) {
        await LocalStorageService.deleteFile(_prefsFile);
      } else {
        await LocalStorageService.writeJsonFile(_prefsFile, data);
      }
    });
  }

  /// Removes [key] from [tutorial_prefs.json] and from legacy prefs JSON on disk.
  ///
  /// [getBool] migrates missing keys from legacy files; without this, dev
  /// `CLEAR_STORAGE` could delete only the new file while legacy still had
  /// `app_has_launched_before: true`, so the tutorial prompt never appeared.
  static Future<void> clearKeyIncludingLegacy(String key) async {
    await remove(key);

    final appName = dotenv.env['APP_NAME'] ?? 'app';
    final docsDir = await getApplicationDocumentsDirectory();
    final candidates = <String>[
      path.join(docsDir.path, '${appName}_prefs.json'),
      path.join(docsDir.path, '${appName}_prefs', '${appName}_prefs.json'),
    ];

    for (final candidatePath in candidates) {
      try {
        final file = File(candidatePath);
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        if (!decoded.containsKey(key)) continue;
        decoded.remove(key);
        if (decoded.isEmpty) {
          await file.delete();
        } else {
          await file.writeAsString(jsonEncode(decoded));
        }
      } catch (_) {
        // Ignore malformed legacy files.
      }
    }
  }

  static Future<bool?> _readLegacyBool(String key) async {
    final appName = dotenv.env['APP_NAME'] ?? 'app';
    final docsDir = await getApplicationDocumentsDirectory();
    final candidates = <String>[
      path.join(docsDir.path, '${appName}_prefs.json'),
      path.join(docsDir.path, '${appName}_prefs', '${appName}_prefs.json'),
    ];

    for (final candidatePath in candidates) {
      try {
        final file = File(candidatePath);
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final value = decoded[key];
        if (value is bool) return value;
      } catch (_) {
        // Ignore malformed legacy files and keep scanning.
      }
    }
    return null;
  }

  /// Serializes writes so read-modify-write updates cannot race and corrupt JSON.
  static Future<void> _serializeWrite(Future<void> Function() operation) {
    final next = _pendingWrite.then((_) => operation());
    _pendingWrite = next.catchError((_) {});
    return next;
  }

  /// Reads prefs map and self-heals malformed files by resetting them.
  static Future<Map<String, dynamic>> _readPrefsOrEmpty() async {
    final data = await LocalStorageService.readJsonFile(_prefsFile);
    if (data != null) return data;

    final exists = await LocalStorageService.fileExists(_prefsFile);
    if (exists) {
      await LocalStorageService.deleteFile(_prefsFile);
    }
    return <String, dynamic>{};
  }
}
