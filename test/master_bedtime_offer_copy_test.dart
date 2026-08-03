import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/master_bedtime_offer_copy.dart';

void main() {
  group('MasterBedtimeOfferCopy', () {
    test('냥할배는 취침 전 제안을 냥할배 말투로 한다', () {
      final templates = MasterBedtimeOfferCopy.templatesForCoach(
        coachId: 'nyang_halbae',
        displayTime: '오후 11:00',
      );

      for (final text in templates) {
        expect(text, contains('냥'));
        expect(text, isNot(contains('대표님')));
        expect(text, isNot(contains('주무셔야')));
        expect(text, isNot(contains('않았습니다')));
        expect(text, isNot(contains('드릴까요')));
        expect(text, isNot(contains('으신가요')));
      }
    });

    test('냥할배 옛 id도 냥할배 문구를 고른다', () {
      final templates = MasterBedtimeOfferCopy.templatesForCoach(
        coachId: 'sec_male',
        displayTime: '오후 11:00',
      );

      expect(templates.first, contains('냥'));
      expect(templates.first, isNot(contains('대표님')));
    });

    test('비서 실장은 비서형 문구를 유지한다', () {
      final templates = MasterBedtimeOfferCopy.templatesForCoach(
        coachId: 'sec_female',
        displayTime: '오후 11:00',
      );

      expect(templates, contains(contains('대표님')));
      expect(templates, contains(contains('설정해 두신 취침 시간')));
    });
  });
}
