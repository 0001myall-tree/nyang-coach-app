import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/life_pattern_service.dart';

/// 설문 답이 기기 사이에서 덮이지 않는지.
///
/// 대화에서 겪은 것과 같은 병이었다. 며칠 안 켠 기기를 켜면 그 낡은 뭉치가
/// 그동안 다른 기기에서 답한 것을 지웠고, 사용자에게는 답한 것이 사라져
/// 보였다.
void main() {
  Map<String, dynamic> decode(String raw) =>
      Map<String, dynamic>.from(jsonDecode(raw) as Map);

  Map<String, dynamic> answersOf(String raw, String coachId) =>
      Map<String, dynamic>.from(
        (decode(raw)[coachId] as Map)['answers'] as Map,
      );

  String store(
    String coachId, {
    required Map<String, dynamic> answers,
    required String askedAt,
    Map<String, dynamic>? notes,
    String? reviewedAt,
  }) => jsonEncode({
    coachId: {
      'answers': answers,
      if (notes != null) 'notes': notes,
      'askedAt': askedAt,
      if (reviewedAt != null) 'reviewedAt': reviewedAt,
    },
  });

  test('한쪽에만 있는 문항은 양쪽 다 남는다', () {
    final local = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-09-10T10:00:00.000',
    );
    final cloud = store(
      'nyang_cat',
      answers: {'style': '필요할 때 그때그때'},
      askedAt: '2026-09-11T10:00:00.000',
    );

    final merged = answersOf(
      LifePatternService.mergedValue(local, cloud),
      'nyang_cat',
    );

    expect(merged['live'], '혼자 살아');
    expect(merged['style'], '필요할 때 그때그때');
  });

  test('겹치는 문항은 마지막으로 답한 쪽이 남는다', () {
    final older = store(
      'nyang_cat',
      answers: {'style': '아침이나 저녁 시간을 정해서'},
      askedAt: '2026-09-01T10:00:00.000',
    );
    final newer = store(
      'nyang_cat',
      answers: {'style': '특정 요일에 몰아서'},
      askedAt: '2026-09-12T10:00:00.000',
    );

    expect(
      answersOf(
        LifePatternService.mergedValue(older, newer),
        'nyang_cat',
      )['style'],
      '특정 요일에 몰아서',
    );
    // 어느 쪽을 로컬로 두든 결과가 같아야 한다.
    expect(
      answersOf(
        LifePatternService.mergedValue(newer, older),
        'nyang_cat',
      )['style'],
      '특정 요일에 몰아서',
    );
  });

  test('낡은 클라우드 값이 방금 한 답을 지우지 않는다', () {
    final justAnswered = store(
      'nyang_cat',
      answers: {'live': '혼자 살아', 'style': '특정 요일에 몰아서'},
      askedAt: '2026-09-12T22:00:00.000',
    );
    final staleCloud = store(
      'nyang_cat',
      answers: {'live': '가족과 살아'},
      askedAt: '2026-08-20T10:00:00.000',
    );

    final merged = answersOf(
      LifePatternService.mergedValue(justAnswered, staleCloud),
      'nyang_cat',
    );

    expect(merged['live'], '혼자 살아');
    expect(merged['style'], '특정 요일에 몰아서');
  });

  test('코치가 다르면 서로 건드리지 않는다', () {
    final local = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-09-10T10:00:00.000',
    );
    final cloud = store(
      'nyang_bro',
      answers: {'doing': '걷기'},
      askedAt: '2026-09-11T10:00:00.000',
    );

    final merged = decode(LifePatternService.mergedValue(local, cloud));

    expect((merged['nyang_cat'] as Map)['answers'], {'live': '혼자 살아'});
    expect((merged['nyang_bro'] as Map)['answers'], {'doing': '걷기'});
  });

  test('코치에게 넘길 문장도 문항 단위로 합쳐진다', () {
    final local = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      notes: {
        'live': ['혼자 산다.'],
      },
      askedAt: '2026-09-10T10:00:00.000',
    );
    final cloud = store(
      'nyang_cat',
      answers: {'style': '특정 요일에 몰아서'},
      notes: {
        'style': ['특정 요일에 몰아서 하는 쪽이 편함.'],
      },
      askedAt: '2026-09-11T10:00:00.000',
    );

    final notes = Map<String, dynamic>.from(
      (decode(LifePatternService.mergedValue(local, cloud))['nyang_cat']
              as Map)['notes']
          as Map,
    );

    expect(notes['live'], ['혼자 산다.']);
    expect(notes['style'], ['특정 요일에 몰아서 하는 쪽이 편함.']);
  });

  test('다시 확인한 시각은 늦은 쪽으로 남는다', () {
    // 이른 쪽이 남으면 방금 확인하고도 또 묻는다.
    final reviewedToday = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-08-01T10:00:00.000',
      reviewedAt: '2026-09-12T10:00:00.000',
    );
    final reviewedLongAgo = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-09-11T10:00:00.000',
      reviewedAt: '2026-07-01T10:00:00.000',
    );

    final merged = decode(
      LifePatternService.mergedValue(reviewedLongAgo, reviewedToday),
    );

    expect(
      (merged['nyang_cat'] as Map)['reviewedAt'],
      '2026-09-12T10:00:00.000',
    );
  });

  test('한쪽이 비어 있으면 있는 쪽을 그대로 쓴다', () {
    final cloud = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-09-10T10:00:00.000',
    );

    expect(
      answersOf(LifePatternService.mergedValue(null, cloud), 'nyang_cat')['live'],
      '혼자 살아',
    );
    expect(
      answersOf(LifePatternService.mergedValue('', cloud), 'nyang_cat')['live'],
      '혼자 살아',
    );
    expect(
      answersOf(LifePatternService.mergedValue(cloud, null), 'nyang_cat')['live'],
      '혼자 살아',
    );
  });

  test('깨진 값이 와도 멀쩡한 쪽을 안 버린다', () {
    final local = store(
      'nyang_cat',
      answers: {'live': '혼자 살아'},
      askedAt: '2026-09-10T10:00:00.000',
    );

    expect(
      answersOf(
        LifePatternService.mergedValue(local, '{이건 JSON이 아니다'),
        'nyang_cat',
      )['live'],
      '혼자 살아',
    );
  });
}
