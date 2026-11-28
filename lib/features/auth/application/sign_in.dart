import '../domain/entities/auth_types.dart';
import '../domain/repositories/auth_ports.dart';

/// A local scope switch failed after the server accepted the credentials.
///
/// The facade logs the original error and converts this into the existing
/// `LOCAL_SCOPE_FAILED` API error, so screens keep one failure type.
class AuthScopeException implements Exception {
  const AuthScopeException(this.error, this.stack);

  final Object error;
  final StackTrace stack;
}

/// Completes a successful register/login/Google response.
///
/// The local scope switches first: a session saved while writes still target
/// the previous account's file is the bug this ordering prevents.
class SignIn {
  SignIn({
    required this.gateway,
    required this.session,
    required this.scope,
  });

  final AuthGateway gateway;
  final SessionStorage session;
  final AccountScope scope;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String displayName = '',
    String? department,
  }) async {
    final response = await gateway.register(
      email: email,
      password: password,
      displayName: displayName,
      department: department,
    );
    return _complete(response);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await gateway.login(email: email, password: password);
    return _complete(response);
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    final response = await gateway.signInWithGoogle();
    return _complete(response);
  }

  Future<Map<String, dynamic>> signUpWithGoogle({
    required String displayName,
    required String department,
  }) async {
    final response = await gateway.signUpWithGoogle(
      displayName: displayName,
      department: department,
    );
    return _complete(response);
  }

  Future<Map<String, dynamic>> _complete(AuthResponse response) async {
    final userId = response.user['id'];
    if (userId is! int) {
      throw const AuthApiException(
        "Couldn't open the local schedule on this phone. Try again.",
        code: 'LOCAL_SCOPE_FAILED',
      );
    }

    try {
      await scope.ensureForUser(userId);
    } catch (error, stack) {
      throw AuthScopeException(error, stack);
    }

    await session.save(
      token: response.token,
      user: response.user,
      expiresIso: response.expiresAt,
    );
    return response.user;
  }
}
