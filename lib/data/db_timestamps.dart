/// UTC timestamp for every local sync mutation.
///
/// The delta queries (`updated_at > lastPushAt`) and the last-write-wins guard
/// compare these strings, so they are always UTC ISO-8601 values.
String utcStamp() => DateTime.now().toUtc().toIso8601String();

/// Parses a sync timestamp (ISO-8601 in UTC) for last-write-wins checks.
///
/// Returns null when there is no usable timestamp, meaning the guard is
/// inactive and the incoming server row should win.
DateTime? parseInstant(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
