import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/memory_service.dart';

/// 매 턴 가는 '요즘 신경 쓰는 일' 한 줄.
///
/// 지난 요약 전체는 코치가 부를 때만 간다. 그런데 모르는 것은 달라고 할 수가
/// 없어서, 이름만은 늘 보낸다.
void main() {
  Map<String, dynamic> day(String date, List<String> onMind) => {
    'date': date,
    'on_mind': onMind,
  };

  test('여러 날에 걸친 이름을 모으고 겹치면 하나로', () {
    final names = MemoryService.recentOnMind([
      day('2026-09-08', ['상견례']),
      day('2026-09-09', ['상견례', '이사 준비']),
      day('2026-09-10', ['이사 준비']),
    ]);

    expect(names.toSet(), {'상견례', '이사 준비'});
    expect(names.length, 2);
  });

  test('최근 것이 앞에 온다', () {
    final names = MemoryService.recentOnMind([
      day('2026-09-08', ['공모전']),
      day('2026-09-10', ['상견례']),
    ]);

    expect(names.first, '상견례');
  });

  test('개수가 차면 최근 것이 남는다', () {
    final names = MemoryService.recentOnMind([
      day('2026-09-05', ['가장 오래된 것']),
      day('2026-09-06', ['가5', '가4']),
      day('2026-09-07', ['가3', '가2']),
      day('2026-09-08', ['가장 최근 것']),
    ], max: 3);

    expect(names.length, 3);
    expect(names.first, '가장 최근 것');
    expect(names.contains('가장 오래된 것'), isFalse);
  });

  test('일주일 넘은 날은 안 본다', () {
    final names = MemoryService.recentOnMind([
      day('2026-09-01', ['지난주 일']),
      for (var d = 4; d <= 10; d++) day('2026-09-0$d', ['이번주 일']),
    ]);

    expect(names, ['이번주 일']);
  });

  test('적어둔 게 없으면 빈 목록', () {
    expect(MemoryService.recentOnMind([]), isEmpty);
    expect(
      MemoryService.recentOnMind([
        day('2026-09-10', []),
        day('2026-09-11', ['  ']),
      ]),
      isEmpty,
    );
  });

  test('이 칸이 생기기 전에 쌓인 요약도 견딘다', () {
    final names = MemoryService.recentOnMind([
      {'date': '2026-09-09', 'achieved': '뭔가 함'},
      day('2026-09-10', ['상견례']),
      'JSON이 깨져서 문자열이 들어온 경우',
    ]);

    expect(names, ['상견례']);
  });

  test('문자열로 저장된 옛 형식도 읽는다', () {
    final names = MemoryService.recentOnMind([
      {'date': '2026-09-10', 'on_mind': '상견례, 이사 준비'},
    ]);

    expect(names, ['상견례', '이사 준비']);
  });
}
