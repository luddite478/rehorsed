import 'package:flutter/foundation.dart';
import '../models/library_item.dart';
import 'local_storage_service.dart';

/// Service for managing library locally
/// Stores library items in library.json file
class LocalLibraryService {
  static const String _libraryFile = 'library.json';

  /// Load library from local storage
  static Future<List<LibraryItem>> loadLibrary() async {
    try {
      final jsonArray = await LocalStorageService.readJsonArrayFile(_libraryFile);
      final items = jsonArray.map((json) => LibraryItem.fromJson(json)).toList();
      debugPrint('📚 [LIBRARY] Loaded ${items.length} items');
      return items;
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error loading library: $e');
      return [];
    }
  }

  /// Add item to library
  static Future<bool> addItem(LibraryItem item) async {
    try {
      final items = await loadLibrary();
      
      // Check if item already exists
      if (items.any((i) => i.id == item.id)) {
        debugPrint('⚠️ [LIBRARY] Item already exists: ${item.id}');
        return false;
      }
      
      // Add new item at the beginning (most recent first)
      items.insert(0, item);
      
      // Save back to file
      final jsonArray = items.map((i) => i.toJson()).toList();
      final success = await LocalStorageService.writeJsonArrayFile(_libraryFile, jsonArray);
      
      if (success) {
        debugPrint('📚 [LIBRARY] Added item: ${item.id}');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error adding item: $e');
      return false;
    }
  }

  /// Remove item from library
  static Future<bool> removeItem(String itemId) async {
    try {
      final items = await loadLibrary();
      
      // Remove item from list
      final initialLength = items.length;
      items.removeWhere((i) => i.id == itemId);
      
      if (items.length == initialLength) {
        debugPrint('⚠️ [LIBRARY] Item not found: $itemId');
        return false;
      }
      
      // Save updated list
      final jsonArray = items.map((i) => i.toJson()).toList();
      final success = await LocalStorageService.writeJsonArrayFile(_libraryFile, jsonArray);
      
      if (success) {
        debugPrint('📚 [LIBRARY] Removed item: $itemId');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error removing item: $e');
      return false;
    }
  }

  /// Get all items (alias for loadLibrary for consistency)
  static Future<List<LibraryItem>> getItems() async {
    return await loadLibrary();
  }

  /// Replace entire library file (e.g. after path repair).
  static Future<bool> writeItems(List<LibraryItem> items) async {
    try {
      final jsonArray = items.map((i) => i.toJson()).toList();
      return await LocalStorageService.writeJsonArrayFile(_libraryFile, jsonArray);
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error writing library: $e');
      return false;
    }
  }

  /// Clear all library items (for testing/reset)
  static Future<bool> clearAll() async {
    try {
      await LocalStorageService.deleteFile(_libraryFile);
      debugPrint('📚 [LIBRARY] Cleared all items');
      return true;
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error clearing library: $e');
      return false;
    }
  }
}
