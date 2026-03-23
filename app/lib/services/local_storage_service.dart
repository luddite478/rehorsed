import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Base service for JSON file-based local storage
/// Provides common functionality for reading/writing JSON files
class LocalStorageService {
  static Directory? _appDocDir;

  /// Initialize and get the app documents directory
  static Future<Directory> getAppDocumentsDirectory() async {
    _appDocDir ??= await getApplicationDocumentsDirectory();
    return _appDocDir!;
  }

  /// Read JSON file from app documents directory
  static Future<Map<String, dynamic>?> readJsonFile(String relativePath) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      
      if (!await file.exists()) {
        debugPrint('📂 [STORAGE] File does not exist: $relativePath');
        return null;
      }
      
      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;
      debugPrint('📂 [STORAGE] Read file: $relativePath');
      return json;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error reading file $relativePath: $e');
      return null;
    }
  }

  /// Write JSON file to app documents directory
  static Future<bool> writeJsonFile(
    String relativePath,
    Map<String, dynamic> data,
  ) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      
      // Create parent directories if they don't exist
      await file.parent.create(recursive: true);
      
      final jsonString = jsonEncode(data);
      await file.writeAsString(jsonString);
      debugPrint('📂 [STORAGE] Wrote file: $relativePath');
      return true;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error writing file $relativePath: $e');
      return false;
    }
  }

  /// Read JSON array file
  static Future<List<Map<String, dynamic>>> readJsonArrayFile(
    String relativePath,
  ) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      
      if (!await file.exists()) {
        debugPrint('📂 [STORAGE] File does not exist: $relativePath');
        return [];
      }
      
      final contents = await file.readAsString();
      final jsonArray = jsonDecode(contents) as List<dynamic>;
      final result = jsonArray
          .map((item) => item as Map<String, dynamic>)
          .toList();
      debugPrint('📂 [STORAGE] Read array file: $relativePath (${result.length} items)');
      return result;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error reading array file $relativePath: $e');
      return [];
    }
  }

  /// Write JSON array file
  static Future<bool> writeJsonArrayFile(
    String relativePath,
    List<Map<String, dynamic>> data,
  ) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      
      // Create parent directories if they don't exist
      await file.parent.create(recursive: true);
      
      final jsonString = jsonEncode(data);
      await file.writeAsString(jsonString);
      debugPrint('📂 [STORAGE] Wrote array file: $relativePath (${data.length} items)');
      return true;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error writing array file $relativePath: $e');
      return false;
    }
  }

  /// Delete file
  static Future<bool> deleteFile(String relativePath) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      
      if (await file.exists()) {
        await file.delete();
        debugPrint('📂 [STORAGE] Deleted file: $relativePath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error deleting file $relativePath: $e');
      return false;
    }
  }

  /// Delete directory recursively
  static Future<bool> deleteDirectory(String relativePath) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final directory = Directory('${dir.path}/$relativePath');
      
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        debugPrint('📂 [STORAGE] Deleted directory: $relativePath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error deleting directory $relativePath: $e');
      return false;
    }
  }

  /// Check if file exists
  static Future<bool> fileExists(String relativePath) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final file = File('${dir.path}/$relativePath');
      return await file.exists();
    } catch (e) {
      debugPrint('❌ [STORAGE] Error checking file existence $relativePath: $e');
      return false;
    }
  }

  /// List files in directory
  static Future<List<String>> listFiles(String relativePath) async {
    try {
      final dir = await getAppDocumentsDirectory();
      final directory = Directory('${dir.path}/$relativePath');
      
      if (!await directory.exists()) {
        return [];
      }
      
      final entities = await directory.list().toList();
      final files = entities
          .whereType<File>()
          .map((file) => file.path.split('/').last)
          .toList();
      return files;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error listing files in $relativePath: $e');
      return [];
    }
  }
}
