enum SyncOutcome { success, skipped, failed }

/// The result of one sync operation.
///
/// A skip is not an error: it means the session or scope was not ready, so no
/// request was made. Only a failure updates the controller's `lastError`.
class SyncResult {
  const SyncResult.success() : outcome = SyncOutcome.success, message = null;
  const SyncResult.skipped([this.message]) : outcome = SyncOutcome.skipped;
  const SyncResult.failed(this.message) : outcome = SyncOutcome.failed;

  final SyncOutcome outcome;
  final String? message;

  bool get isSuccess => outcome == SyncOutcome.success;
  bool get isFailure => outcome == SyncOutcome.failed;
}
