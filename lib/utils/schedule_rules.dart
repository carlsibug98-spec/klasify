import '../models/class_item.dart';

/// Returns the first class that overlaps [startMinutes]..[endMinutes].
/// Classes ending exactly when another starts are allowed.
ClassItem? findOverlappingClass(
  Iterable<ClassItem> classes, {
  required int day,
  required int startMinutes,
  required int endMinutes,
  int? excludeId,
}) {
  for (final item in classes) {
    if (item.day != day || item.id == excludeId) continue;
    if (startMinutes < item.endMinutes && endMinutes > item.startMinutes) {
      return item;
    }
  }
  return null;
}
