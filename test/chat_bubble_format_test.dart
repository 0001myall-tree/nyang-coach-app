import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/chat_bubble_format.dart';

String wrap(String text) => ChatBubbleFormat.wrap(text);

void main() {
  _tidyAfterTagsTests();

  group('긴 문장 뒤에는 줄을 바꾼다', () {
    test('앞 문장이 길면 다음 문장이 새 줄로 간다', () {
      expect(
        wrap('오늘은 생각보다 많이 걸어왔구나. 여기서 하나만 더 해보자.'),
        '오늘은 생각보다 많이 걸어왔구나.\n여기서 하나만 더 해보자.',
      );
    });

    test('세 문장이면 각각 길이를 보고 정한다', () {
      // 첫 문장 길다 → 줄바꿈. 둘째는 짧다 → 붙인다.
      expect(
        wrap('오래 붙잡고 있으면 집중이 떨어지는 게 당연하다냥. 잠깐 걷자. 돌아와서 짧게 다시 해보자냥.'),
        '오래 붙잡고 있으면 집중이 떨어지는 게 당연하다냥.\n잠깐 걷자. 돌아와서 짧게 다시 해보자냥.',
      );
    });

    test('물음표와 느낌표에서도 끊는다', () {
      expect(
        wrap('지금 마음이 제일 덜 무거운 일이 뭐야? 그거 하나만 골라보자.'),
        '지금 마음이 제일 덜 무거운 일이 뭐야?\n그거 하나만 골라보자.',
      );
    });
  });

  group('짧은 문장끼리는 붙여 둔다', () {
    test('짧은 대꾸는 한 줄로 남는다', () {
      // "응. 알겠어."까지 두 줄이면 오히려 산만하다.
      expect(wrap('응. 알겠어.'), '응. 알겠어.');
    });

    test('딱 열다섯 글자면 끊는다', () {
      const fifteen = '가나다라마바사아자차카타파하.'; // 15자
      expect(wrap('$fifteen 다음 문장.'), '$fifteen\n다음 문장.');
    });

    test('열네 글자면 붙인다', () {
      const fourteen = '가나다라마바사아자차카타파.'; // 14자
      expect(wrap('$fourteen 다음 문장.'), '$fourteen 다음 문장.');
    });
  });

  group('건드리면 안 되는 것', () {
    test('코치가 이미 줄을 나눠 보냈으면 그대로 둔다', () {
      const already = '집사, 오늘 습관 하나가 아직 비어 있다냥.\n이미 했으면 눌러주라냥.';
      expect(wrap(already), already);
    });

    test('한 문장이면 그대로다', () {
      const one = '오늘은 여기까지만 해도 충분하다냥.';
      expect(wrap(one), one);
    });

    test('소수점은 문장 끝이 아니다', () {
      // 마침표 뒤에 공백이 없으면 자르지 않는다.
      expect(wrap('3.5시간쯤 걸릴 것 같은데 괜찮겠어?'), '3.5시간쯤 걸릴 것 같은데 괜찮겠어?');
    });

    test('빈 문자열도 깨지지 않는다', () {
      expect(wrap(''), '');
    });

    test('글자는 하나도 잃지 않는다', () {
      const text = '오래 붙잡고 있었구나. 잠깐 쉬었다 오자. 돌아오면 20분만 해보자냥.';
      final wrapped = wrap(text);
      expect(
        wrapped.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' '),
        text,
      );
    });
  });

  group('이모지', () {
    test('이모지를 두 글자로 세지 않는다', () {
      // runes로 안 세면 이모지 하나가 둘로 잡혀 짧은 문장이 길다고 판정된다.
      const short = '수고했어요 🌸.'; // 이모지 포함 9자
      expect(wrap('$short 오늘은 여기까지.'), '$short 오늘은 여기까지.');
    });
  });
}

void _tidyAfterTagsTests() {
  group('태그를 뗀 자리', () {
    test('문장 끝에 남은 쉼표를 치운다', () {
      // 실제로 나갔던 답변이다. "[TASK: …]," 에서 태그만 떼면 쉼표가 남는다.
      expect(
        ChatBubbleFormat.tidyAfterTags('두 번째는 좀 더 쉬워진다냥. ,'),
        '두 번째는 좀 더 쉬워진다냥.',
      );
    });

    test('부호 앞에 벌어진 공백을 붙인다', () {
      expect(ChatBubbleFormat.tidyAfterTags('알겠다냥 .'), '알겠다냥.');
    });

    test('줄 끝에 남은 부호를 치운다', () {
      expect(ChatBubbleFormat.tidyAfterTags('오늘도 잘했다냥ㅋㅋ ,'), '오늘도 잘했다냥ㅋㅋ');
    });

    test('멀쩡한 문장은 건드리지 않는다', () {
      const line = '설거지, 빨래 둘 다 했구나. 오늘 잘했다냥!';
      expect(ChatBubbleFormat.tidyAfterTags(line), line);
    });

    test('여러 줄에서도 각 줄 끝을 본다', () {
      expect(
        ChatBubbleFormat.tidyAfterTags('첫 줄이다냥 ,\n둘째 줄이다냥.'),
        '첫 줄이다냥\n둘째 줄이다냥.',
      );
    });
  });
}
