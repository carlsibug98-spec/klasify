import 'dart:math' as math;

/// A text block with its bounding box, in image pixel coordinates.
class SpatialTextBlock {
  const SpatialTextBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 0,
  });

  final String text;
  final double left, top, right, bottom;
  final double confidence;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;
}

/// Result of assigning text blocks to grid cells.
class CellAssignment {
  const CellAssignment({required this.columnIndex, required this.band});

  /// Index into the day-column boundary list (block belongs between
  /// bounds[columnIndex] and bounds[columnIndex + 1]).
  final int columnIndex;

  /// Index into the horizontal rule list: the block sits inside the band
  /// between rowRules[band] and rowRules[band + 1].
  final int band;
}

/// Assigns each OCR text block to a grid cell by **centroid** rather than
/// reading order. Reading-order assignment breaks on two-line subjects or
/// slightly rotated pages; nearest-band logic is stable under both.
class CentroidCellAssigner {
  CentroidCellAssigner({required this.columnBounds, required this.rowRules});

  /// Vertical day-column edges, ascending (n+1 entries for n day columns).
  final List<double> columnBounds;

  /// Horizontal rule positions, ascending.
  final List<int> rowRules;

  CellAssignment? assign(SpatialTextBlock block) {
    if (columnBounds.length < 2 || rowRules.length < 2) return null;
    final x = block.centerX;
    if (x < columnBounds.first || x > columnBounds.last) return null;

    var column = -1;
    for (var i = 0; i < columnBounds.length - 1; i++) {
      if (x >= columnBounds[i] && x <= columnBounds[i + 1]) {
        column = i;
        break;
      }
    }
    if (column < 0) return null;

    // Use the block's vertical center but clamp so a tall two-line subject
    // still lands in the band containing most of its ink.
    final y = block.centerY;
    var band = -1;
    for (var i = 0; i < rowRules.length - 1; i++) {
      if (y >= rowRules[i] && y <= rowRules[i + 1]) {
        band = i;
        break;
      }
    }
    if (band < 0) {
      // Nearest band fallback for blocks sitting a few pixels outside rules.
      var bestDistance = double.infinity;
      for (var i = 0; i < rowRules.length - 1; i++) {
        final center = (rowRules[i] + rowRules[i + 1]) / 2;
        final distance = (center - y).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          band = i;
        }
      }
      final bandHeight = (rowRules[band + 1] - rowRules[band]).toDouble();
      if (bestDistance > bandHeight * 1.2) return null;
    }
    return CellAssignment(columnIndex: column, band: band);
  }

  /// Groups blocks per (column, band) cell key like "d{col}r{band}".
  Map<String, List<SpatialTextBlock>> groupCells(
    Iterable<SpatialTextBlock> blocks,
  ) {
    final cells = <String, List<SpatialTextBlock>>{};
    for (final block in blocks) {
      final assignment = assign(block);
      if (assignment == null) continue;
      final key = 'd${assignment.columnIndex}r${assignment.band}';
      cells.putIfAbsent(key, () => []).add(block);
    }
    return cells;
  }
}

/// A class entry merged across consecutive bands it spans (labs, tutorials).
class MergedCellSpan {
  const MergedCellSpan({
    required this.columnIndex,
    required this.startBand,
    required this.endBand,
    required this.blocks,
  });

  final int columnIndex;
  final int startBand;
  final int endBand;
  final List<SpatialTextBlock> blocks;
}

/// Detects multi-period classes from merged cells using two complementary
/// signals and merges their per-band fragments into a single span:
///
/// 1. **Missing internal rule**: printed merged cells have no horizontal line
///    between the bands they cover. When [rulesByColumn] shows the rule at a
///    band boundary absent (or faint) inside one column while present in its
///    neighbours, that boundary is a merge seam.
/// 2. **Vertical continuation**: an empty band directly below a non-empty one
///    whose upper text block extends into it (a big centered "CHEM LAB" box)
///    is treated as the same class.
List<MergedCellSpan> mergeCellSpans({
  required Map<String, List<SpatialTextBlock>> cells,
  required int columnCount,
  required int bandCount,
  Map<int, Set<int>>? strongRuleRowsByColumn,
  allRuleRows,
}) {
  final spans = <MergedCellSpan>[];
  final consumed = <String>{};

  bool rulePresent(int column, int row) {
    if (strongRuleRowsByColumn == null || allRuleRows == null) return true;
    // Only trust the seam test when the column has enough data overall.
    final own = strongRuleRowsByColumn[column];
    if (own == null) return true;
    // Consider rows within +-3 px of the expected rule position.
    for (final candidate in allRuleRows) {
      if ((candidate - row).abs() <= 3 && !own.contains(candidate)) {
        return false;
      }
    }
    return true;
  }

  for (var column = 0; column < columnCount; column++) {
    var band = 0;
    while (band < bandCount) {
      final key = 'd${column}r$band';
      final firstBlocks = cells[key];
      if (firstBlocks == null || firstBlocks.isEmpty) {
        band++;
        continue;
      }
      final mergedBlocks = [...firstBlocks];
      var endBand = band;

      var next = band + 1;
      while (next < bandCount) {
        final nextKey = 'd${column}r$next';
        final nextBlocks = cells[nextKey] ?? const <SpatialTextBlock>[];
        final seamRow = next; // rule index separating band-1 and band
        final seamMissing = !rulePresent(column, seamRow);

        var continuation = false;
        if (nextBlocks.isEmpty && mergedBlocks.isNotEmpty) {
          final lowest = mergedBlocks
              .map((block) => block.bottom)
              .reduce(math.max);
          final bandTop = seamRow.toDouble();
          // Upper text physically reaches into the empty band below.
          continuation = lowest > bandTop + 2;
        }

        if (seamMissing || continuation) {
          mergedBlocks.addAll(nextBlocks);
          endBand = next;
          consumed.add(nextKey);
          next++;
        } else {
          break;
        }
      }

      consumed.add(key);
      spans.add(
        MergedCellSpan(
          columnIndex: column,
          startBand: band,
          endBand: endBand,
          blocks: mergedBlocks,
        ),
      );
      band = endBand + 1;
    }
  }
  return spans;
}
