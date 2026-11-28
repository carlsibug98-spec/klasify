/// Whether a stored session should be refreshed before its next use.
///
/// A missing expiry (old installs) counts as "refresh me". The window is ten
/// minutes: a token exactly ten minutes away is still accepted, matching the
/// previous `isBefore` check.
bool shouldRefreshSession(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return true;
  return expiresAt.isBefore(now.add(const Duration(minutes: 10)));
}
