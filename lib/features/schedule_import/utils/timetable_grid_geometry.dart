double? inferTimetableRowSpacing({
  required List<double> gridRulePositions,
  required List<double> ocrTickPositions,
  required double maxGap,
}) {
  List<double> intervals(List<double> positions) {
    final sorted = [...positions]..sort();
    final values = <double>[];
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > 3 && gap < maxGap) values.add(gap);
    }
    values.sort();
    return values;
  }

  final gridIntervals = intervals(gridRulePositions);
  final candidates = gridIntervals.isNotEmpty
      ? gridIntervals
      : intervals(ocrTickPositions);
  if (candidates.isEmpty) return null;
  return candidates[candidates.length ~/ 2];
}
