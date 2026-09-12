import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/chat_store.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 대화를 남기는 방식.
///
/// 대화는 원래 자정마다 방에서 보관함으로 **옮겨졌고**, 옮기고 나서 방을
/// 비웠다. 옮기는 일은 어긋날 자리가 많았다 — 정리가 두 번 돌 때, 늦게 돌 때,
/// 다른 기기가 먼저 돌 때, 옮기다 멈출 때. 게다가 같은 정리가 두 곳에 있었는데
/// 비우는 줄만 있고 보관하는 줄이 없는 쪽이 있었다. 그 쪽이 이긴 날에는 대화가
/// 남는 곳 없이 사라졌다.
///
/// 지금은 방 하나에 그대로 쌓고 오래된 **날짜**만 버린다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> line(String time, String text) => {
    'time': time,
    'text': text,
    'isUser': true,
  };

  List<dynamic> datedLines(List<String> dates) => [
    for (final date in dates) line('${date}T09:00:00', '$date에 한 말'),
  ];

  Set<String> datesOf(List<dynamic> messages) => {
    for (final message in messages) ChatStore.dateOf(message)!,
  };

  group('대화한 날 7개를 남긴다', () {
    test('날짜가 일곱 개까지는 하나도 안 버린다', () {
      final messages = datedLines([
        '2026-09-01',
        '2026-09-02',
        '2026-09-03',
        '2026-09-04',
        '2026-09-05',
        '2026-09-06',
        '2026-09-07',
      ]);

      expect(ChatStore.keepRecentDates(messages).length, 7);
    });

    test('여덜 번째 날이 생기면 가장 오래된 날만 버린다', () {
      final messages = datedLines([
        '2026-09-01',
        '2026-09-02',
        '2026-09-03',
        '2026-09-04',
        '2026-09-05',
        '2026-09-06',
        '2026-09-07',
        '2026-09-08',
      ]);

      final kept = ChatStore.keepRecentDates(messages);

      expect(datesOf(kept), isNot(contains('2026-09-01')));
      expect(datesOf(kept), contains('2026-09-02'));
      expect(datesOf(kept), contains('2026-09-08'));
    });

    test('한 날에 여러 마디가 있어도 날짜 하나로 센다', () {
      final messages = [
        for (var hour = 9; hour < 20; hour++)
          line('2026-09-01T$hour:00:00', '$hour시'),
        ...datedLines([
          '2026-09-02',
          '2026-09-03',
          '2026-09-04',
          '2026-09-05',
          '2026-09-06',
          '2026-09-07',
        ]),
      ];

      final kept = ChatStore.keepRecentDates(messages);

      expect(kept.length, messages.length);
    });

    test('열흘 만에 열어도 지난 일곱 번의 대화가 남아 있다', () {
      // 날수로 자르면 여기서 대화가 통째로 없어졌다 — 오랜만에 온 사람 앞에
      // 코치가 아무것도 기억 못 하는 채로 앉는다.
      final messages = datedLines([
        '2026-06-01',
        '2026-06-08',
        '2026-07-02',
        '2026-07-20',
        '2026-08-03',
        '2026-08-19',
        '2026-09-01',
      ]);

      final kept = ChatStore.keepRecentDates(messages);

      expect(kept.length, 7);
      expect(datesOf(kept), contains('2026-06-01'));
    });

    test('시각을 못 읽는 항목은 어느 날 것인지 모르니 남긴다', () {
      final messages = [
        {'text': '시각 없는 말', 'isUser': false},
        ...datedLines([
          '2026-09-01',
          '2026-09-02',
          '2026-09-03',
          '2026-09-04',
          '2026-09-05',
          '2026-09-06',
          '2026-09-07',
          '2026-09-08',
        ]),
      ];

      final kept = ChatStore.keepRecentDates(messages);

      expect(kept.any((m) => (m as Map)['text'] == '시각 없는 말'), isTrue);
    });

    test('아주 많이 쌓이면 개수 상한에서 최근 것만 남긴다', () {
      final messages = [
        for (var i = 0; i < 30; i++)
          line('2026-09-01T09:${i.toString().padLeft(2, '0')}:00', '$i번째'),
      ];

      final kept = ChatStore.keepRecentDates(messages, limit: 10);

      expect(kept.length, 10);
      expect((kept.first as Map)['text'], '20번째');
      expect((kept.last as Map)['text'], '29번째');
    });
  });

  group('대화 두 뭉치를 합칠 때', () {
    test('같은 말은 한 번만 남는다', () {
      // 기기 두 대가 같은 날 대화하면 겹치는 구간이 생긴다. 덮으면 한쪽이
      // 사라지므로 합친다.
      final merged = ChatStore.merge(
        [line('2026-09-01T09:00:00', '안녕')],
        [line('2026-09-01T09:00:00', '안녕'), line('2026-09-01T10:00:00', '뭐해')],
      );

      expect(merged.length, 2);
    });

    test('시간순으로 세운다', () {
      final merged = ChatStore.merge(
        [line('2026-09-01T15:00:00', '늦은 말')],
        [line('2026-09-01T09:00:00', '이른 말')],
      );

      expect((merged.first as Map)['text'], '이른 말');
    });

    test('같은 말이 겹치면 앞에 준 쪽이 남는다', () {
      // 확인 카드를 누르면 앱은 그 말은 남기고 버튼만 걷어낸다. 걷어낸 것과
      // 걷어내기 전 것은 글자가 같아서 같은 말로 읽힌다. 옛 쪽이 이기면 눌렀던
      // 버튼이 되살아나 또 누를 수 있게 된다.
      final withButtons = {
        'time': '2026-09-01T09:00:00',
        'text': '등록할까요?',
        'isUser': false,
        'choices': ['네', '아니요'],
      };
      final consumed = {
        'time': '2026-09-01T09:00:00',
        'text': '등록할까요?',
        'isUser': false,
      };

      final merged = ChatStore.merge([consumed], [withButtons]);

      expect(merged.length, 1);
      expect((merged.first as Map).containsKey('choices'), isFalse);
    });

    test('같은 시각에 사용자와 코치가 각각 말한 것은 둘 다 남는다', () {
      final merged = ChatStore.merge([], [
        {'time': '2026-09-01T09:00:00', 'text': '같은 말', 'isUser': true},
        {'time': '2026-09-01T09:00:00', 'text': '같은 말', 'isUser': false},
      ]);

      expect(merged.length, 2);
    });
  });

  group('자정 정리가 대화에 하는 일', () {
    test('대화를 비우지 않는다', () async {
      // 여기가 이번 사고의 자리다. 정리 한 벌이 보관 없이 방을 비웠고, 먼저
      // 도착한 쪽이 이기기 때문에 기기마다 결과가 갈렸다.
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-10T21:00:00', '어제 한 말'),
          line('2026-09-11T09:00:00', '오늘 한 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await DailyResetService.pruneChatHistories(prefs);

      final kept = ChatStore.decode(prefs.getString('nyang_chat_history_cat'));
      expect(kept.length, 2);
    });

    test('옛 보관함에 있던 것을 방으로 합쳐 들이고 보관함을 비운다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-11T09:00:00', '오늘 한 말'),
        ]),
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-10T21:00:00', '보관함에 있던 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await DailyResetService.pruneChatHistories(prefs);

      final kept = ChatStore.decode(prefs.getString('nyang_chat_history_cat'));
      expect(kept.length, 2);
      expect((kept.first as Map)['text'], '보관함에 있던 말');
      expect(
        prefs.containsKey('${DailyResetService.chatArchivePrefix}cat'),
        isFalse,
      );
    });

    test('보관함에 옛 버전이 있어도 방에 있는 지금 값이 남는다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          {'time': '2026-09-10T21:00:00', 'text': '등록할까요?', 'isUser': false},
        ]),
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          {
            'time': '2026-09-10T21:00:00',
            'text': '등록할까요?',
            'isUser': false,
            'choices': ['네'],
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await DailyResetService.pruneChatHistories(prefs);

      final kept = ChatStore.decode(prefs.getString('nyang_chat_history_cat'));
      expect(kept.length, 1);
      expect((kept.first as Map).containsKey('choices'), isFalse);
    });

    test('두 번 돌아도 대화가 늘거나 줄지 않는다', () async {
      // 업데이트 안 한 다른 기기가 보관함에 다시 적어 올릴 수 있어서, 합치기는
      // 볼 때마다 돈다. 여러 번 돌아도 같아야 한다.
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-11T09:00:00', '오늘 한 말'),
        ]),
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-10T21:00:00', '보관함에 있던 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await DailyResetService.pruneChatHistories(prefs);
      final after = prefs.getString('nyang_chat_history_cat');
      await DailyResetService.pruneChatHistories(prefs);

      expect(prefs.getString('nyang_chat_history_cat'), after);
    });

    test('여덜째 날이 되면 가장 오래된 날만 걷어낸다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode(
          datedLines([
            '2026-09-01',
            '2026-09-02',
            '2026-09-03',
            '2026-09-04',
            '2026-09-05',
            '2026-09-06',
            '2026-09-07',
            '2026-09-08',
          ]),
        ),
      });
      final prefs = await SharedPreferences.getInstance();

      await DailyResetService.pruneChatHistories(prefs);

      final kept = ChatStore.decode(prefs.getString('nyang_chat_history_cat'));
      expect(kept.length, 7);
      expect(datesOf(kept), isNot(contains('2026-09-01')));
    });
  });
}
