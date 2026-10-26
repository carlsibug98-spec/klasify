import 'dart:math' as math;

/// A detected straight rule (table line) in a binarized page.
class GridRule {
  const GridRule({
    required this.isHorizontal,
    required this.position,
    required this.start,
    required this.end,
    required this.strength,
  });

  final bool isHorizontal;

  /// Row (horizontal rules) or column (vertical rules) index of the peak.
  final int position;

  /// Along-axis extent of the dark run.
  final int start;
  final int end;

  /// Fraction of the along-axis span covered by ink at this rule.
  final double strength;

  double get length => (end - start).toDouble();
}

/// Finds table rules from per-line ink profiles using adaptive peak detection
/// instead of fixed pixel thresholds. [profiles] maps an axis index (row or
/// column number) to its dark-pixel count and the extents of its longest
/// contiguous dark run. A line qualifies as a rule when its ink count stands
/// out from the median line (signal-to-noise) *and* its longest run spans a
/// meaningful fraction of the page — so faint gray rules on cheap printouts
/// are still caught while dense text columns never produce false rules.
List<GridRule> detectAdaptiveRules({
  required Map<int, ({int ink, int runStart, int runEnd})> profiles,
  required int axisLength,
  required bool isHorizontal,
  double minRunFraction = .5,
  double prominenceFactor = 3.0,
  double minAbsoluteFraction = .12,
}) {
  if (axisLength <= 0 || profiles.isEmpty) return [];

  final inkValues = profiles.values.map((p) => p.ink).toList()..sort();
  final medianInk = inkValues[inkValues.length ~/ 2];
  // Noise floor: median plus a margin so pages with heavy text still work.
  final noiseFloor = math.max(medianInk.toDouble(), axisLength * .04);
  final minRun = axisLength * minRunFraction;
  final minInk = math.max(
    axisLength * minAbsoluteFraction,
    noiseFloor * prominenceFactor,
  );

  final candidates = <GridRule>[];
  for (final entry in profiles.entries) {
    final p = entry.value;
    if (p.ink < minInk) continue;
    if ((p.runEnd - p.runStart) < minRun) continue;
    candidates.add(
      GridRule(
        isHorizontal: isHorizontal,
        position: entry.key,
        start: p.runStart,
        end: p.runEnd,
        strength: (p.ink / axisLength).clamp(0.0, 1.0),
      ),
    );
  }

  // Merge adjacent candidate lines (rules render 1-3 px thick) keeping the
  // strongest member of each cluster.
  candidates.sort((a, b) => a.position.compareTo(b.position));
  final merged = <GridRule>[];
  for (final rule in candidates) {
    if (merged.isNotEmpty && rule.position - merged.last.position <= 3) {
      if (rule.strength > merged.last.strength) {
        merged[merged.length - 1] = rule;
      }
    } else {
      merged.add(rule);
    }
  }
  return merged;
}

/// Builds the row ink profile for horizontal-rule detection from a grayscale
/// RGBA buffer (R channel holds luminance after normalization).
Map<int, ({int ink, int runStart, int runEnd})> buildRowProfiles({
  required List<int> pixels,
  required int width,
  required int height,
  int top = 0,
  int bottom = -1,
  int darkValue = 105,
}) {
  final end = bottom < 0 ? height : math.min(bottom, height);
  final profiles = <int, ({int ink, int runStart, int runEnd})>{};
  for (var y = math.max(top, 0); y < end; y++) {
    var ink = 0;
    var bestStart = 0, bestEnd = 0, currentStart = -1;
    for (var x = 0; x < width; x++) {
      final value = pixels[(y * width + x) * 4];
      if (value < darkValue) {
        ink++;
        if (currentStart < 0) currentStart = x;
        if (x - currentStart > bestEnd - bestStart) {
          bestStart = currentStart;
          bestEnd = x;
        }
      } else {
        currentStart = -1;
      }
    }
    profiles[y] = (ink: ink, runStart: bestStart, runEnd: bestEnd);
  }
  return profiles;
}

/// Groups parallel rules into evenly spaced grids and reports the dominant
/// spacing, which lets callers synthesize missing rules (faint or broken
/// printed lines) at consistent intervals.
({double? spacing, int count}) estimateRuleSpacing(List<GridRule> rules) {
  if (rules.length < 3) {
    return (spacing: null, count: rules.length);
  }
  final gaps = <double>[];
  for (var i = 1; i < rules.length; i++) {
    final gap = (rules[i].position - rules[i - 1].position).toDouble();
    if (gap > 3) gaps.add(gap);
  }
  if (gaps.isEmpty) return (spacing: null, count: rules.length);
  gaps.sort();
  final medianGap = gaps[gaps.length ~/ 2];
  final inliers = gaps
      .where((gap) => (gap - medianGap).abs() <= medianGap * .25)
      .length;
  if (inliers < gaps.length * .6) return (spacing: null, count: rules.length);
  return (spacing: medianGap, count: rules.length);
}
