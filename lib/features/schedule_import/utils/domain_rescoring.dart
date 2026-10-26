import 'dart:math' as math;

/// Domain-aware correction of OCR text using a small, timetable-specific
/// vocabulary: course-code patterns, common room tokens, and confusable
/// characters. Everything here is conservative — a token is only rewritten
/// when it nearly matches a known vocabulary entry or follows a pattern that
/// is unambiguously a code/time.

/// Normalizes characters PaddleOCR commonly confuses inside codes and times.
String normalizeOcrTokens(String text) {
  var result = text;
  // Time-like tokens with letter-for-digit slips: "9:3O" -> "9:30",
  // "l2:00" -> "12:00", "8；OO AM" -> "8:00 AM".
  result = result.replaceAllMapped(
    RegExp(r'(\d)\s*[:：oO]\s*([oO0-9]\d|\d[oO])'),
    (m) {
      final digits = m.group(2)!.replaceAll('O', '0').replaceAll('o', '0');
      return '${m.group(1)}:$digits';
    },
  );
  // Full-width punctuation that OCR confuses with ASCII separators, plus
  // letter-for-digit slips inside the minutes field of a time token:
  // "8；OO AM" -> "8:00 AM", "9：3o" -> "9:30".
  result = result.replaceAll(RegExp(r'[:：；]'), ':');
  result = result.replaceAllMapped(
    RegExp(r'(?<=\d:)([oO0-9])([oO])'),
    (m) => '${m.group(1) == 'o' || m.group(1) == 'O' ? '0' : m.group(1)}0',
  );
  result = result
      .replaceAll(RegExp(r'\bl(?=\d)'), '1')
      .replaceAll(RegExp(r'(?<=\d)l\b'), '1')
      .replaceAll(RegExp(r'(?<=[A-Z])I(?=\d)'), '1')
      .replaceAll('；', ':')
      .replaceAll('，', ',');
  // Trailing period after a meridiem ("9:30 A.M." is fine) but strip
  // doubled dots inside codes: "CS..201" -> "CS.201".
  result = result.replaceAll(RegExp(r'\.{2,}'), '.');
  return result;
}

/// Fuzzy-corrects a scanned course code (e.g. "as20i" -> "CS201") against a
/// vocabulary of codes the student already has or a campus catalog. Matching
/// ignores case/punctuation and allows one edit for short codes, two for long.
class CourseCodeRescorer {
  CourseCodeRescorer(Iterable<String> vocabulary)
    : _vocabulary = {for (final entry in vocabulary) _canonical(entry): entry};

  final Map<String, String> _vocabulary;

  static String _canonical(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Visual OCR confusions applied to every character of a canonical token:
  /// O↔0, I/L↔1, S↔5, B↔8, Z↔2. The map is transitive-closed so chains like
  /// A→4→H count as one confusion (A vs H), not two separate slips.
  static const Map<String, List<String>> _confusions = {
    'O': ['0'],
    '0': ['O'],
    'I': ['1', 'L'],
    'L': ['1', 'I'],
    '1': ['I', 'L'],
    'S': ['5'],
    '5': ['S'],
    'B': ['8'],
    '8': ['B'],
    'Z': ['2'],
    '2': ['Z'],
    'A': ['4'],
    '4': ['A'],
  };

  /// True when [a] and [b] have equal length and differ only in positions
  /// where the characters are visual OCR confusions (e.g. AS20I vs CS201).
  static bool _isConfusionVariant(String a, String b) {
    if (a.length != b.length) return false;
    var differs = false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i]) continue;
      final confusable = _confusions[a[i]];
      if (confusable == null || !confusable.contains(b[i])) return false;
      differs = true;
    }
    return differs;
  }

  /// Similarity score in [0, 1]: fraction of positions that either match or
  /// are a single visual confusion. Used to pick among multiple candidates.
  static double _confusionScore(String a, String b) {
    if (a.length != b.length) return 0;
    var ok = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i] || (_confusions[a[i]]?.contains(b[i]) ?? false)) ok++;
    }
    return ok / a.length;
  }

  /// Returns the closest vocabulary entry when [token] is within an edit
  /// budget scaled to its length, otherwise returns [token] unchanged.
  String correct(String token) {
    final canonical = _canonical(token);
    if (canonical.length < 3) return token;
    if (_vocabulary.containsKey(canonical)) return _vocabulary[canonical]!;

    String? best;
    var bestDistance = 99;
    var bestScore = 0.0;
    for (final entry in _vocabulary.entries) {
      // Confusion-aware match first: equal-length tokens whose differences
      // are all visual OCR slips (AS20I -> CS201) beat plain edit distance,
      // which would otherwise need edits at every mismatched position. The
      // best-scoring candidate wins so ambiguous vocabularies stay stable.
      final score = _confusionScore(canonical, entry.key);
      if (_isConfusionVariant(canonical, entry.key) && score > bestScore) {
        bestScore = score;
        best = entry.value;
      }
    }
    if (best != null) return best;
    for (final entry in _vocabulary.entries) {
      final maxEdits = canonical.length <= 5 ? 1 : 2;
      final distance = _confusionAwareDistance(canonical, entry.key, maxEdits);
      if (distance > 0 && distance <= maxEdits && distance < bestDistance) {
        bestDistance = distance;
        best = entry.value;
      }
    }
    return best ?? token;
  }

  /// Edit distance where substituting visually confusable characters
  /// (O/0, I/L/1, S/5, ...) costs nothing — OCR slips are not real edits.
  static int _confusionAwareDistance(String a, String b, int limit) {
    if ((a.length - b.length).abs() > limit) return limit + 1;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final same =
            a[i - 1] == b[j - 1] ||
            (_confusions[a[i - 1]]?.contains(b[j - 1]) ?? false);
        final cost = same ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
        if (current[j] < rowMin) rowMin = current[j];
      }
      if (rowMin > limit) return limit + 1;
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }
}
