import '../domain/repositories/auth_ports.dart';

/// PATCH /auth/me followed by a local user refresh.
class UpdateProfile {
  UpdateProfile({required this.gateway, required this.session});

  final AuthGateway gateway;
  final SessionStorage session;

  Future<Map<String, dynamic>> call({String? displayName, String? email}) async {
    final user = await gateway.updateProfile(
      displayName: displayName,
      email: email,
    );
    await session.persistUser(user);
    return user;
  }
}
