import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/domain/entities/auth_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 28, 12);

  test('a session without a stored expiry is refreshed', () {
    expect(shouldRefreshSession(null, now), isTrue);
  });

  test('an expired session is refreshed', () {
    expect(
      shouldRefreshSession(now.subtract(const Duration(seconds: 1)), now),
      isTrue,
    );
  });

  test('a session inside the ten-minute window is refreshed', () {
    expect(
      shouldRefreshSession(
        now.add(const Duration(minutes: 9, seconds: 59)),
        now,
      ),
      isTrue,
    );
  });

  test('exactly ten minutes away is not refreshed', () {
    expect(
      shouldRefreshSession(now.add(const Duration(minutes: 10)), now),
      isFalse,
    );
  });

  test('a session beyond the window is not refreshed', () {
    expect(
      shouldRefreshSession(
        now.add(const Duration(minutes: 10, seconds: 1)),
        now,
      ),
      isFalse,
    );
  });
}
