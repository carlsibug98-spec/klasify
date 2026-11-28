import '../domain/repositories/auth_ports.dart';

/// Changes the password, then drops the session the server just revoked.
class ChangePassword {
  ChangePassword({required this.gateway, required this.session});

  final AuthGateway gateway;
  final SessionStorage session;

  Future<void> call({
    required String currentPassword,
    required String newPassword,
  }) async {
    await gateway.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    // The server bumps token_version, which revokes this token as well.
    // Drop the local session instead of leaving the UI in a half-signed-in
    // state that fails on the next request.
    await session.clear();
  }
}
