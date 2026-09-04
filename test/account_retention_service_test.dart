import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/account_retention_service.dart';

void main() {
  group('AccountRetentionService', () {
    test('마지막 로그인으로부터 3년 뒤를 폐기 가능 시각으로 잡는다', () {
      final loginAt = DateTime.utc(2026, 9, 4, 12, 30);

      expect(
        AccountRetentionService.retentionDeleteAfter(loginAt),
        DateTime.utc(2029, 9, 4, 12, 30),
      );
    });
  });
}
