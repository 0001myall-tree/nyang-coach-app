import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/repeat_keyword_service.dart';

Map<String, dynamic> day(String date, List<String> texts, {String? category}) {
  return {
    'date': date,
    'tasks': texts
        .map((text) => {'text': text, 'category': category ?? 'today'})
        .toList(),
  };
}

List<String> keywordsOf(List<dynamic> records) =>
    RepeatKeywordService.analyze(records).map((k) => k.keyword).toList();

void main() {
  group('반복되는 말 찾기', () {
    test('회차만 다른 할 일에서 공통 키워드를 뽑는다', () {
      final records = [
        day('2026-08-10', ['1화 쓰기']),
        day('2026-08-11', ['2화 쓰기']),
        day('2026-08-12', ['3화 쓰기']),
      ];
      expect(keywordsOf(records), contains('쓰기'));
    });

    test('글쓰기와 쓰기를 같은 말로 센다', () {
      final records = [
        day('2026-08-10', ['1화 쓰기']),
        day('2026-08-11', ['매일 글쓰기']),
        day('2026-08-12', ['2화 쓰기']),
      ];
      final found = RepeatKeywordService.analyze(records);
      final writing = found.firstWhere((k) => k.keyword == '쓰기');
      expect(writing.days, 3);
    });

    test('이틀만 나오면 후보가 아니다', () {
      final records = [
        day('2026-08-10', ['1화 쓰기']),
        day('2026-08-11', ['2화 쓰기']),
      ];
      expect(keywordsOf(records), isEmpty);
    });

    test('하루에 몰아 적어도 하루로 센다', () {
      final records = [
        day('2026-08-10', ['1화 쓰기', '2화 쓰기', '3화 쓰기']),
      ];
      expect(keywordsOf(records), isEmpty);
    });

    test('주 2회를 두 주 하면 걸린다', () {
      final records = [
        day('2026-08-04', ['운동하기']),
        day('2026-08-07', ['운동']),
        day('2026-08-11', ['운동하기']),
        day('2026-08-14', ['운동']),
      ];
      final found = RepeatKeywordService.analyze(records);
      expect(found.first.keyword, '운동');
      expect(found.first.days, 4);
    });

    test('습관에서 온 할 일은 세지 않는다', () {
      final records = [
        day('2026-08-10', ['물 마시기'], category: 'habit'),
        day('2026-08-11', ['물 마시기'], category: 'habit'),
        day('2026-08-12', ['물 마시기'], category: 'habit'),
      ];
      expect(keywordsOf(records), isEmpty);
    });

    test('너무 흔한 말은 후보가 아니다', () {
      final records = [
        day('2026-08-10', ['방 정리하기']),
        day('2026-08-11', ['서류 정리']),
        day('2026-08-12', ['사진 정리']),
      ];
      expect(keywordsOf(records), isNot(contains('정리')));
    });

    test('두 주보다 오래된 기록은 보지 않는다', () {
      final records = [
        for (var i = 1; i <= 3; i++) day('2026-07-0$i', ['1화 쓰기']),
        for (var i = 1; i <= 14; i++)
          day('2026-08-${i.toString().padLeft(2, '0')}', ['청소']),
      ];
      expect(keywordsOf(records), isNot(contains('쓰기')));
    });
  });

  group('오늘 할 일이 후보에 걸리는지', () {
    final candidates = [const RepeatKeyword('쓰기', 4)];

    test('회차가 바뀐 새 할 일도 걸린다', () {
      expect(RepeatKeywordService.matchingKeyword('4화 쓰기', candidates), '쓰기');
    });

    test('후보보다 긴 이름도 걸린다', () {
      expect(RepeatKeywordService.matchingKeyword('에세이 글쓰기', candidates), '쓰기');
    });

    test('상관없는 일은 안 걸린다', () {
      expect(RepeatKeywordService.matchingKeyword('장보기', candidates), isNull);
    });
  });

  group('말이 망가지지 않는다', () {
    test('명사 끝 글자를 조사로 착각하지 않는다', () {
      expect(RepeatKeywordService.keywordsOf('회의'), contains('회의'));
      expect(RepeatKeywordService.keywordsOf('고양이 밥'), contains('고양이'));
    });

    test('조사는 뗀다', () {
      expect(RepeatKeywordService.keywordsOf('보고서를'), contains('보고서'));
    });
  });
}
