enum SyncOutcome { success, skipped, failed }

/// The result of one sync operation.
///
/// A skip is not an error: it means the session or scope was not ready, so no
/// request was made. Only a failure updates the controller's `lastError`.
class SyncResult {
  const SyncResult.success({this.conflicts = 0})
    : outcome = SyncOutcome.success,
      message = null;
  const SyncResult.skipped([this.message])
    : outcome = SyncOutcome.skipped,
      conflicts = 0;
  const SyncResult.failed(this.message)
    : outcome = SyncOutcome.failed,
      conflicts = 0;

  final SyncOutcome outcome;
  final String? message;

  /// Server rows discarded because this phone held a strictly newer edit.
  /// Zero on skips and failures; LWW itself is unchanged.
  final int conflicts;

  bool get isSuccess => outcome == SyncOutcome.success;
  bool get isFailure => outcome == SyncOutcome.failed;
}
