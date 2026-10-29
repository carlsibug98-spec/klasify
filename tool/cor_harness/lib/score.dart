/// Port of bench6's ground-truth matching and metric computation, plus the
/// room/professor field checks that only matter for COR fixtures.
library;

import 'dart:math' as math;

class TruthClass {
  const TruthClass({
    required this.subject,
    required this.day,
    required this.start,
    required this.end,
    required this.room,
    required this.professor,
  });

  final String subject;
  final int day;
  final int start;
  final int end;
  final String room;
  final String professor;
}

class ParsedRow {
  const ParsedRow(
    this.subject,
    this.day,
    this.startMinutes,
    this.endMinutes,
    this.room,
    this.professor,
  );

  final String subject;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final String room;
  final String professor;
}

class Match {
  const Match(this.truthIndex, this.rowIndex, this.score);

  final int truthIndex;
  final int rowIndex;
  final double score;
}

int dayIndex(String name) {
  final key = name.toLowerCase().trim();
  const days = {
    'mon': 1, 'monday': 1,
    'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'weds': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };
  return days[key] ?? 0;
}

int minutes(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts.length > 1 ? int.parse(parts[1]) : 0;
  return h * 60 + m;
}

String norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double similarity(String a, String b) {
  final x = norm(a);
  final y = norm(b);
  if (x.isEmpty && y.isEmpty) return 1.0;
  final longest = math.max(x.length, y.length);
  if (longest == 0) return 1.0;
  return 1.0 - levenshtein(x, y) / longest;
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = math.min(
        math.min(curr[j] + 1, prev[j + 1] + 1),
        prev[j] + cost,
      );
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length];
}

/// Greedy 1-to-1 matching, identical to bench6.
List<Match> matchGreedy(List<TruthClass> truth, List<ParsedRow> rows) {
  final candidates = <Match>[];
  for (var t = 0; t < truth.length; t++) {
    for (var r = 0; r < rows.length; r++) {
      if (truth[t].day != rows[r].day) continue;
      final overlaps =
          truth[t].start < rows[r].endMinutes &&
          rows[r].startMinutes < truth[t].end;
      if (!overlaps) continue;
      final score = similarity(truth[t].subject, rows[r].subject);
      if (score >= 0.34) candidates.add(Match(t, r, score));
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final usedT = <int>{};
  final usedR = <int>{};
  final matches = <Match>[];
  for (final c in candidates) {
    if (usedT.contains(c.truthIndex) || usedR.contains(c.rowIndex)) continue;
    usedT.add(c.truthIndex);
    usedR.add(c.rowIndex);
    matches.add(c);
  }
  return matches;
}

double r3(double value) => (value * 1000).roundToDouble() / 1000;
