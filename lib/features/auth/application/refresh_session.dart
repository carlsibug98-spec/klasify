import '../domain/entities/auth_types.dart';
import '../domain/repositories/auth_ports.dart';

/// What happened to a silent refresh attempt.
enum SessionRefreshStatus {
  /// No stored token, so there was nothing to refresh.
  noSession,

  /// A fresh token is in place.
  refreshed,

  /// The server rejected the session and it was cleared.
  rejected,

  /// The server was unreachable; the session is unchanged.
  unreachable,

  /// A logout or new sign-in replaced the token while the request was in
  /// flight; the response was discarded.
  superseded,

  /// The refreshed token could not be persisted; the old session is intact.
  storageFailed,
}

/// Refreshes the stored session without letting an old response overwrite a
/// newer one.
class RefreshSession {
  RefreshSession({required this.gateway, required this.session});

  final AuthGateway gateway;
  final SessionStorage session;

  Future<SessionRefreshStatus> call() async {
    final stored = await session.readToken();
    if (stored == null) return SessionRefreshStatus.noSession;

    final result = await gateway.refreshToken(stored);

    // A logout or a new sign-in may have replaced the session while the
    // request was in flight. A response for the old token must never be
    // applied to the new one.
    if (await session.readToken() != stored) {
      return SessionRefreshStatus.superseded;
    }

    switch (result.outcome) {
      case RefreshOutcome.unreachable:
        // Network hiccup or server down: keep the session, callers retry.
        return SessionRefreshStatus.unreachable;
      case RefreshOutcome.rejected:
        // Rejected (deleted user, revoked identity): end the local session.
        await session.clear();
        return SessionRefreshStatus.rejected;
      case RefreshOutcome.refreshed:
        try {
          await session.applyRefresh(
            token: result.token!,
            expiresIso: result.expiresAt,
            user: result.user,
          );
        } catch (_) {
          // Preserve the original contract: a storage failure is treated like
          // any other refresh failure and keeps the existing session.
          return SessionRefreshStatus.storageFailed;
        }
        return SessionRefreshStatus.refreshed;
    }
  }
}
