import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 지나간 하루의 대화를 날짜로 다시 모으는 자리.
///
/// 하루 요약은 원래 자정 정리 안에서만 만들어졌고, 정리가 건너뛴 날은 영영
/// 비어 있었다. 뒤늦게 만들려면 그 대화를 다시 찾아야 하는데, 정리가 이미
/// 지나갔다면 현재 기록에는 오늘 것밖에 없고 어제 것은 보관함에 있다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> line(String time, String text) => {
    'time': time,
    'text': text,
    'isUser': true,
  };

  group('지나간 하루의 대화를 모을 때', () {
    test('보관함으로 옮겨간 어제 대화를 찾아온다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-11T09:00:00', '오늘 첫 마디'),
        ]),
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-10T21:00:00', '어제 한 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      final messages = DailyResetService.collectChatHistoryForDate(
        prefs,
        '2026-09-10',
      );

      expect(messages.length, 1);
      expect((messages.first as Map)['text'], '어제 한 말');
    });

    test('아직 옮겨지지 않았으면 현재 기록에서 찾아온다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-10T21:00:00', '어제 한 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      final messages = DailyResetService.collectChatHistoryForDate(
        prefs,
        '2026-09-10',
      );

      expect(messages.length, 1);
    });

    test('양쪽에 다 있어도 한 번만 센다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_chat_history_cat': jsonEncode([
          line('2026-09-10T21:00:00', '어제 한 말'),
        ]),
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-10T21:00:00', '어제 한 말'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        DailyResetService.collectChatHistoryForDate(prefs, '2026-09-10').length,
        1,
      );
    });

    test('다른 날 대화는 섞지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-09T21:00:00', '그저께'),
          line('2026-09-10T21:00:00', '어제'),
          line('2026-09-11T09:00:00', '오늘'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      final messages = DailyResetService.collectChatHistoryForDate(
        prefs,
        '2026-09-10',
      );

      expect(messages.length, 1);
      expect((messages.first as Map)['text'], '어제');
    });

    test('시각을 모르는 말은 두고 간다', () async {
      SharedPreferences.setMockInitialValues({
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          {'text': '언제 한 말인지 모름', 'isUser': true},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        DailyResetService.collectChatHistoryForDate(prefs, '2026-09-10'),
        isEmpty,
      );
    });

    test('여러 코치의 말을 시간순으로 합친다', () async {
      SharedPreferences.setMockInitialValues({
        '${DailyResetService.chatArchivePrefix}cat': jsonEncode([
          line('2026-09-10T21:00:00', '나중'),
        ]),
        '${DailyResetService.chatArchivePrefix}bro': jsonEncode([
          line('2026-09-10T08:00:00', '먼저'),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      final messages = DailyResetService.collectChatHistoryForDate(
        prefs,
        '2026-09-10',
      );

      expect(messages.map((m) => (m as Map)['text']).toList(), ['먼저', '나중']);
      expect((messages.first as Map)['coachId'], 'bro');
    });
  });
}
