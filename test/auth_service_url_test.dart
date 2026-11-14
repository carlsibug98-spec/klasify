import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/auth_service.dart';

void main() {
  test('release API URL policy requires absolute HTTPS', () {
    expect(AuthService.isSecureApiUrl('https://api.klasify.app/v1'), isTrue);
    expect(AuthService.isSecureApiUrl('https://192.168.1.67/klasify-api'), isTrue);

    expect(AuthService.isSecureApiUrl('http://192.168.1.67/klasify-api'), isFalse);
    expect(AuthService.isSecureApiUrl('https:///missing-host'), isFalse);
    expect(AuthService.isSecureApiUrl('not a url'), isFalse);
    expect(AuthService.isSecureApiUrl(''), isFalse);
  });
}
