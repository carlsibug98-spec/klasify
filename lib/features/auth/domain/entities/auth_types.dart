/// Typed auth API error: the backend message plus its semantic code, so
/// screens can branch on codes (EMAIL_EXISTS, INVALID_CREDENTIALS, ...)
/// without parsing strings. `toString()` returns the message only.
class AuthApiException implements Exception {
  const AuthApiException(
    this.message, {
    this.code = 'UNKNOWN',
    this.statusCode = 0,
  });
  final String message;
  final String code;
  final int statusCode;

  @override
  String toString() => message;
}

/// A successful register/login/Google response.
class AuthResponse {
  const AuthResponse({required this.token, required this.user, this.expiresAt});

  factory AuthResponse.fromJson(Map<String, dynamic> data) => AuthResponse(
    token: data['token'] as String,
    user: data['user'] as Map<String, dynamic>,
    expiresAt: data['expires_at'] as String?,
  );

  final String token;
  final Map<String, dynamic> user;
  final String? expiresAt;
}

/// Outcome of a silent `/auth/refresh` attempt.
enum RefreshOutcome {
  /// A fresh token (and possibly a fresh user payload) is available.
  refreshed,

  /// The server rejected the session; the caller should clear it.
  rejected,

  /// The server could not be reached or returned an unparseable body; keep
  /// the stored session and retry later.
  unreachable,
}

class RefreshResult {
  const RefreshResult._(this.outcome, {this.token, this.expiresAt, this.user});

  factory RefreshResult.refreshed({
    required String token,
    String? expiresAt,
    Map<String, dynamic>? user,
  }) => RefreshResult._(
    RefreshOutcome.refreshed,
    token: token,
    expiresAt: expiresAt,
    user: user,
  );

  factory RefreshResult.rejected() =>
      const RefreshResult._(RefreshOutcome.rejected);

  factory RefreshResult.unreachable() =>
      const RefreshResult._(RefreshOutcome.unreachable);

  final RefreshOutcome outcome;
  final String? token;
  final String? expiresAt;
  final Map<String, dynamic>? user;
}
