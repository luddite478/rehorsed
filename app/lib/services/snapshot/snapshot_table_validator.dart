import 'package:flutter/foundation.dart';
import '../../state/sequencer/table.dart';

/// Structural validation for [source.table] maps before snapshot import.
///
/// Catches truncated exports (e.g. stale [TableState.sectionsCount]) without
/// mutating native state.
class SnapshotTableValidator {
  SnapshotTableValidator._();

  /// Validates the nested `source.table` object inside a full snapshot map.
  static bool isValidSnapshotSource(Map<String, dynamic>? snapshot,
      {int maxSteps = 2048, int maxCols = 16}) {
    if (snapshot == null) return false;
    final source = snapshot['source'];
    if (source is! Map<String, dynamic>) return false;
    final table = source['table'];
    if (table is! Map<String, dynamic>) return false;
    return isValidTableJson(table, maxSteps: maxSteps, maxCols: maxCols);
  }

  /// Validates a `table` map as produced by [SnapshotExporter._exportTableState].
  static bool isValidTableJson(Map<String, dynamic>? table,
      {int maxSteps = 2048, int maxCols = 16}) {
    if (table == null) return false;
    try {
      final sectionsCount = table['sections_count'];
      if (sectionsCount is! int ||
          sectionsCount < 1 ||
          sectionsCount > TableState.maxSections) {
        debugPrint(
            '❌ [SNAPSHOT_TABLE_VALIDATOR] invalid sections_count: $sectionsCount');
        return false;
      }

      final sections = table['sections'];
      if (sections is! List<dynamic> || sections.length != sectionsCount) {
        debugPrint(
            '❌ [SNAPSHOT_TABLE_VALIDATOR] sections length != sections_count');
        return false;
      }

      var totalSteps = 0;
      for (final s in sections) {
        if (s is! Map<String, dynamic>) return false;
        final numSteps = s['num_steps'];
        if (numSteps is! int || numSteps <= 0 || numSteps > maxSteps) {
          debugPrint(
              '❌ [SNAPSHOT_TABLE_VALIDATOR] invalid num_steps: $numSteps');
          return false;
        }
        totalSteps += numSteps;
      }

      if (totalSteps > maxSteps) {
        debugPrint(
            '❌ [SNAPSHOT_TABLE_VALIDATOR] totalSteps $totalSteps > maxSteps $maxSteps');
        return false;
      }

      final layers = table['layers'];
      if (layers != null) {
        if (layers is! List<dynamic>) return false;
        if (layers.isNotEmpty && layers.length != sectionsCount) {
          debugPrint(
              '❌ [SNAPSHOT_TABLE_VALIDATOR] layers.length ${layers.length} != sectionsCount $sectionsCount');
          return false;
        }
        for (final sectionLayers in layers) {
          if (sectionLayers is! List<dynamic>) return false;
          if (sectionLayers.length > TableState.maxLayersPerSection) {
            return false;
          }
        }
      }

      final tableCells = table['table_cells'];
      if (tableCells is! List<dynamic>) {
        debugPrint('❌ [SNAPSHOT_TABLE_VALIDATOR] table_cells missing or not a list');
        return false;
      }
      if (tableCells.length != totalSteps) {
        debugPrint(
            '❌ [SNAPSHOT_TABLE_VALIDATOR] table_cells.rows ${tableCells.length} != totalSteps $totalSteps');
        return false;
      }

      for (var r = 0; r < tableCells.length; r++) {
        final row = tableCells[r];
        if (row is! List<dynamic>) return false;
        if (row.length != maxCols) {
          debugPrint(
              '❌ [SNAPSHOT_TABLE_VALIDATOR] row $r width ${row.length} != maxCols $maxCols');
          return false;
        }
      }

      return true;
    } catch (e, st) {
      debugPrint('❌ [SNAPSHOT_TABLE_VALIDATOR] $e\n$st');
      return false;
    }
  }
}
