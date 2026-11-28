import '../domain/repositories/auth_ports.dart';

/// Deletes the server account and clears the local session.
///
/// The local schedule detach is a separate step so the facade can notify
/// listeners after the session is cleared but before the file moves, matching
/// the original ordering.
class DeleteAccount {
  DeleteAccount({
    required this.gateway,
    required this.session,
    required this.scope,
  });

  final AuthGateway gateway;
  final SessionStorage session;
  final AccountScope scope;

  /// Returns the deleted account's id, or null when the stored id was not an
  /// integer. Throws when the server delete fails, before any local change.
  Future<int?> deleteServerAccount() async {
    final userId = session.currentUser?['id'];

    // Throws on failure before any local change.
    await gateway.deleteAccount();

    // The account is gone server-side: stop treating its session as current
    // before touching the local file, so an in-flight sync cannot re-scope to
    // the deleted account.
    await session.clear();

    return userId is int ? userId : null;
  }

  Future<void> detach(int userId) => scope.detachAccount(userId);
}
