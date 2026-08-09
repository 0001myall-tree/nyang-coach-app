import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/screens/coach_config.dart';

/// 시각만 바꿔가며 부른다. 화면도 prefs도 필요 없다.
String at(int hour) => CoachConfigs.lifeRoutineSection(
  CoachConfigs.all['halmae']!,
  DateTime(2026, 8, 9, hour, 30),
);

void main() {
  group('할매 시간대 생활 루틴', () {
    test('아침에는 몸을 깨우는 행동을 권한다', () {
      expect(at(7), contains('몸을 깨우는 생활 행동'));
      expect(at(10), contains('몸을 깨우는 생활 행동'));
    });

    test('점심때는 점심을 챙기게 한다', () {
      expect(at(11), contains('점심을 챙기고'));
      expect(at(13), contains('점심을 챙기고'));
    });

    test('저녁에는 저녁 챙기기와 내일 준비를 우선한다', () {
      expect(at(18), contains('저녁 챙기기'));
      expect(at(20), contains('저녁 챙기기'));
    });

    test('밤에는 수면 루틴만 권하고 청소는 권하지 않는다', () {
      expect(at(21), contains('수면 루틴'));
      expect(at(23), contains('수면 루틴'));
      expect(at(23), contains('청소 추천을 하지 않는다'));
    });

    test('한 번에 한 구간만 실린다', () {
      // 밤에 점심 얘기가 섞이면 코치가 엉뚱한 걸 챙긴다. 구간을 나눈 이유가 이것뿐이다.
      expect(at(23), isNot(contains('점심을 챙기고')));
      expect(at(12), isNot(contains('수면 루틴')));
      expect(at(7), isNot(contains('저녁 챙기기')));
    });

    test('규칙이 없던 오후 2~6시에는 아무것도 붙이지 않는다', () {
      expect(at(14), isEmpty);
      expect(at(17), isEmpty);
    });

    test('시간대 지침이 없는 코치에게는 아무것도 붙이지 않는다', () {
      for (final id in ['cat', 'boyfriend', 'bro', 'nyang_halbae', 'sec_female']) {
        expect(
          CoachConfigs.lifeRoutineSection(
            CoachConfigs.all[id]!,
            DateTime(2026, 8, 9, 20, 30),
          ),
          isEmpty,
          reason: '$id는 시간대 지침이 없다',
        );
      }
    });
  });
}
