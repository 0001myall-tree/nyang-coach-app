import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/sync_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 세 값 견주기. 이 기기 값, 클라우드 값, 둘이 마지막으로 같았을 때의 값.
///
/// 예전에는 나중에 올린 쪽이 이겼다. 며칠 꺼져 있던 폰을 켜면 그 폰의 옛
/// 데이터가 통째로 올라가 쓰던 폰의 최근 며칠을 덮었다.
void main() {
  String fp(Object? value) => SyncBase.fingerprint(value)!;

  final monday = fp('[월요일 목록]');
  final friday = fp('[금요일 목록]');
  final edited = fp('[월요일 목록 + 방금 완료]');

  group('며칠 꺼져 있던 폰', () {
    test('이 기기가 그대로면 클라우드를 받는다', () {
      // 월요일에 꺼졌다. 그동안 다른 폰이 금요일까지 올렸다.
      expect(
        SyncBase.decide(local: monday, cloud: friday, base: monday),
        SyncMove.takeCloud,
      );
    });

    test('켜자마자 옛 목록으로 정리가 돌았어도 클라우드를 따른다', () {
      // 받아오기 전에 이 기기에서 뭔가 바뀌었다. 둘 다 바뀐 셈이다.
      expect(
        SyncBase.decide(local: edited, cloud: friday, base: monday),
        SyncMove.takeCloud,
      );
    });

    test('맞춘 기록이 없는 기기(이 기능 이전 빌드)도 클라우드를 따른다', () {
      expect(
        SyncBase.decide(local: monday, cloud: friday, base: null),
        SyncMove.takeCloud,
      );
    });

    test('다른 기기에서 새로 생긴 것을 지우지 않고 받는다', () {
      expect(
        SyncBase.decide(local: null, cloud: friday, base: null),
        SyncMove.takeCloud,
      );
    });
  });

  group('평소', () {
    test('이 기기에서 고친 것은 올린다', () {
      expect(
        SyncBase.decide(local: edited, cloud: monday, base: monday),
        SyncMove.push,
      );
    });

    test('늦게 도착한 옛 스냅샷이 방금 고친 것을 덮지 않는다', () {
      // 받기 쪽에서 push는 "이 기기 것을 둔다"로 읽힌다.
      expect(
        SyncBase.decide(local: edited, cloud: monday, base: monday),
        SyncMove.push,
      );
    });

    test('같으면 할 일이 없다', () {
      expect(
        SyncBase.decide(local: monday, cloud: monday, base: null),
        SyncMove.same,
      );
    });

    test('클라우드에 없는 새 것은 올린다', () {
      expect(
        SyncBase.decide(local: edited, cloud: null, base: null),
        SyncMove.push,
      );
    });

    test('이 기기에서 지운 것은 클라우드에서도 지운다', () {
      expect(
        SyncBase.decide(local: null, cloud: monday, base: monday),
        SyncMove.deleteCloud,
      );
    });

    test('지웠는데 그사이 다른 기기가 고쳤으면 받는다', () {
      expect(
        SyncBase.decide(local: null, cloud: friday, base: monday),
        SyncMove.takeCloud,
      );
    });
  });

  group('지문', () {
    test('이 기기의 문자열 목록과 클라우드에서 온 목록이 같게 찍힌다', () {
      expect(
        SyncBase.fingerprint(<String>['a', '1']),
        SyncBase.fingerprint(<Object>['a', 1]),
      );
    });

    test('글자와 목록은 모양이 같아도 다르게 찍힌다', () {
      expect(
        SyncBase.fingerprint('a'),
        isNot(SyncBase.fingerprint(<String>['a'])),
      );
    });

    test('한 글자만 달라도 다르다', () {
      expect(fp('{"done":true}'), isNot(fp('{"done":fals}')));
      expect(fp('방정리 완료'), isNot(fp('방정리 미완')));
    });
  });

  test('다른 계정으로 적힌 기록은 읽지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SyncBase.write(prefs, 'alice', {'nyang_tasks': monday});

    expect(SyncBase.read(prefs, 'alice'), {'nyang_tasks': monday});
    expect(SyncBase.read(prefs, 'bob'), isEmpty);
  });
}
