import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/models/user_data.dart';
import 'package:nyang_coach/services/coach_id_service.dart';

void main() {
  group('CoachIdService', () {
    test('갓생 형 구버전 ID를 현재 ID로 맞춘다', () {
      expect(CoachIdService.normalize('godlife_bro'), 'bro');
    });
  });

  group('UserData', () {
    test('구버전 갓생 형 소유권도 bro 접근 권한으로 읽는다', () {
      final data = UserData.fromJson({
        'plan_type': 'friends',
        'owned_coaches': ['godlife_bro'],
        'owned_coach_expires_at': {'godlife_bro': null},
      });

      expect(data.ownedCoaches, ['bro']);
      expect(data.canAccessCoach('bro'), isTrue);
    });
  });
}
