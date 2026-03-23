import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/library_item.dart';
import '../services/local_library_service.dart';
import '../utils/local_audio_path.dart';

/// Local-only state for managing library
/// Simplified to work without server synchronization
class LibraryState extends ChangeNotifier {
  // Data
  List<LibraryItem> _library = [];
  
  // UI state
  bool _isLoading = false;
  String? _error;
  
  // Track if initial load is complete
  bool _hasLoaded = false;
  
  final _uuid = const Uuid();
  
  // Getters
  List<LibraryItem> get library => List.unmodifiable(_library);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  
  // ============================================================================
  // Public API methods
  // ============================================================================
  
  /// Load library once on app startup
  Future<void> loadLibrary() async {
    // If already loaded or has items, don't reload
    if (_hasLoaded || _library.isNotEmpty) {
      debugPrint('📚 [LIBRARY] Library already loaded (${_library.length} items)');
      if (!_hasLoaded) {
        _hasLoaded = true;
      }
      return;
    }
    
    try {
      _isLoading = true;
      notifyListeners();
      
      _error = null;
      
      var items = await LocalLibraryService.loadLibrary();
      items = await _repairLibraryPaths(items);
      _library = items;
      _hasLoaded = true;
      
      debugPrint('📚 [LIBRARY] Loaded library: ${_library.length} items');
    } catch (e) {
      _error = 'Failed to load library: $e';
      debugPrint('❌ [LIBRARY] Error loading library: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Add item to library from local file path
  Future<bool> addToLibrary({
    required String localPath,
    required String format,
    String? customName,
    double? duration,
    int? sizeBytes,
    String? sourcePatternId,
    String? sourceCheckpointId,
  }) async {
    // Use custom name if provided, otherwise format as "Oct 5, 2025"
    final String name;
    if (customName != null && customName.isNotEmpty) {
      name = customName;
    } else {
      final now = DateTime.now();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      name = '${months[now.month - 1]} ${now.day}, ${now.year}';
    }
    
    // Create library item
    final item = LibraryItem(
      id: _uuid.v4(),
      name: name,
      localPath: localPath,
      format: format,
      duration: duration,
      sizeBytes: sizeBytes,
      sourcePatternId: sourcePatternId,
      sourceCheckpointId: sourceCheckpointId,
      createdAt: DateTime.now(),
    );
    
    try {
      // Optimistically add to local list
      _library = [item, ..._library];
      notifyListeners();
      
      debugPrint('📚 [LIBRARY] Added to local library: ${item.id}');
      
      // Save to storage
      final success = await LocalLibraryService.addItem(item);
      
      if (!success) {
        // Rollback on failure
        _library = _library.where((i) => i.id != item.id).toList();
        notifyListeners();
        return false;
      }
      
      return true;
    } catch (e) {
      // Rollback on error
      _library = _library.where((i) => i.id != item.id).toList();
      notifyListeners();
      debugPrint('❌ [LIBRARY] Failed to add to library: $e');
      return false;
    }
  }
  
  /// Remove item from library
  Future<bool> removeFromLibrary(String itemId) async {
    // Find and save the item in case we need to rollback
    final removedIndex = _library.indexWhere((i) => i.id == itemId);
    if (removedIndex == -1) {
      debugPrint('❌ [LIBRARY] Item not found: $itemId');
      return false;
    }
    
    final removedItem = _library[removedIndex];
    
    try {
      // Optimistically remove from local list
      _library = List.from(_library)..removeAt(removedIndex);
      notifyListeners();
      
      // Remove from storage
      final success = await LocalLibraryService.removeItem(itemId);
      
      if (!success) {
        // Rollback on failure - restore at original position
        _library = List.from(_library)..insert(removedIndex, removedItem);
        notifyListeners();
        return false;
      }
      
      debugPrint('📚 [LIBRARY] Removed from library: $itemId');
      return true;
    } catch (e) {
      // Rollback on error - restore at original position
      _library = List.from(_library)..insert(removedIndex, removedItem);
      notifyListeners();
      debugPrint('❌ [LIBRARY] Failed to remove from library: $e');
      return false;
    }
  }
  
  /// Update library item name
  Future<bool> updateItemName(String itemId, String newName) async {
    try {
      final index = _library.indexWhere((i) => i.id == itemId);
      if (index == -1) {
        debugPrint('❌ [LIBRARY] Item not found: $itemId');
        return false;
      }
      
      final oldItem = _library[index];
      final updatedItem = oldItem.copyWith(name: newName);
      
      // Update in memory
      _library = List.from(_library)..[index] = updatedItem;
      notifyListeners();
      
      // Note: We don't have an updateItem method in LocalLibraryService
      // We need to remove and re-add to update
      // For now, just update in memory
      // TODO: Add updateItem method to LocalLibraryService if needed
      
      debugPrint('📚 [LIBRARY] Updated item name: $itemId');
      return true;
    } catch (e) {
      debugPrint('❌ [LIBRARY] Error updating item name: $e');
      return false;
    }
  }
  
  /// Fix stale absolute paths (iOS container changes, file://, /var vs /private/var).
  Future<List<LibraryItem>> _repairLibraryPaths(List<LibraryItem> items) async {
    final resolved = await Future.wait(
      items.map((item) => LocalAudioPath.resolve(item.localPath)),
    );
    var changed = false;
    final out = <LibraryItem>[];
    for (var i = 0; i < items.length; i++) {
      final newPath = resolved[i] ?? items[i].localPath;
      if (resolved[i] != null && resolved[i] != items[i].localPath) changed = true;
      out.add(items[i].copyWith(localPath: newPath));
    }
    if (changed) {
      await LocalLibraryService.writeItems(out);
      debugPrint('📚 [LIBRARY] Repaired stale paths in library.json');
    }
    return out;
  }

  /// Clear all data
  void clear() {
    _library = [];
    _hasLoaded = false;
    _error = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('📚 [LIBRARY] Cleared library data');
  }
}
