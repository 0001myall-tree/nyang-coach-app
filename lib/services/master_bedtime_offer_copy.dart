import 'dart:math';

import 'coach_id_service.dart';

/// 마스터 코치의 취침 전 일정 이월 제안 문구.
///
/// 채팅 화면 안에 두면 냥할배/비서 실장 말투가 섞여도 테스트로 잡기 어렵다.
class MasterBedtimeOfferCopy {
  static List<String> templatesForCoach({
    required String coachId,
    required String displayTime,
  }) {
    if (CoachIdService.isNyangHalbae(coachId)) {
      return [
        '그런데 자네는 $displayTime 전에 자야 덜 피곤하다고 했지냥? 남은 계획을 지금 다 하기엔 빠듯해 보인다냥. 혹시 오늘 꼭 끝내야 하는 일이 남아 있냥?',
        '자네가 정해둔 취침 시간($displayTime)이 얼마 안 남았다냥. 오늘 계획 중 일부는 내일로 넘기고 슬슬 잘 준비해보는 건 어떠냥?',
        '벌써 시간이 이렇게 됐다냥. $displayTime 취침 시간을 지키려면 지금 정리가 필요해 보인다냥. 오늘 꼭 해야 하는 것만 남기고 미뤄줄까냥?',
      ];
    }

    return [
      '그런데 대표님은 $displayTime 전에 주무셔야 덜 피곤하다고 하셨죠? 남은 계획을 지금 다 하기엔 빠듯해 보여요. 혹시 오늘까지 꼭 끝내야 하는 일정이 있으신가요?',
      '대표님, 설정해 두신 취침 시간($displayTime)이 얼마 남지 않았습니다. 오늘 계획 중 일부는 내일로 조정하고 슬슬 잘 준비를 해보시는 건 어떨까요?',
      '벌써 시간이 이렇게 되었네요. 대표님이 말씀하신 $displayTime 취침 시간을 지키려면 지금 정리가 필요해 보입니다. 오늘 꼭 해야만 하는 일만 남기고 미뤄드릴까요?',
    ];
  }

  static String pick({
    required String coachId,
    required String displayTime,
    Random? random,
  }) {
    final templates = templatesForCoach(
      coachId: coachId,
      displayTime: displayTime,
    );
    final picker = random ?? Random();
    return templates[picker.nextInt(templates.length)];
  }
}
