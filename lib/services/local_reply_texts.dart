class LocalReplyTexts {
  const LocalReplyTexts._();

  static String todayTaskTimeReply({
    required String coachId,
    required String text,
    required String timeLabel,
  }) {
    if (timeLabel.isEmpty) {
      return switch (coachId) {
        'cat' || 'nyang_halbae' => "오늘 '$text' 시간은 아직 안 잡혀 있다냥.",
        'bro' => "오늘 '$text' 시간은 아직 안 잡혀 있다.",
        'sec_female' => "오늘 '$text' 시간은 아직 정해져 있지 않아요.",
        _ => "오늘 '$text' 시간은 아직 안 잡혀 있어.",
      };
    }
    return switch (coachId) {
      'cat' || 'nyang_halbae' => "오늘 '$text'은 $timeLabel부터다냥.",
      'bro' => "오늘 '$text'은 $timeLabel부터다.",
      'sec_female' => "오늘 '$text'은 $timeLabel부터예요.",
      _ => "오늘 '$text'은 $timeLabel부터야.",
    };
  }

  static String featureLocationMessage({
    required String coachId,
    required String location,
  }) {
    final target = switch (location) {
      'today' => '오늘 할 일',
      'goals' => '목표',
      'vision' => '장기 비전',
      'repeat_schedule' => '반복 일정',
      'repeat_schedule_delete' => '반복 일정',
      'repeat_schedule_edit' => '반복 일정',
      'schedule' => '캘린더',
      'habit' => '루틴',
      'records' => '기록',
      'settings' => '설정',
      'todo_reset' => '오늘 할 일 초기화',
      'task_check' => '할 일 체크',
      _ => '',
    };

    String base(String suffix) => target.isEmpty ? suffix : '$target$suffix';

    return switch (coachId) {
      'cat' => switch (location) {
        'task_check' =>
          '할 일 탭 > 오늘에서 그 항목을 오른쪽으로 끝까지 밀면 완료다냥.',
        'picker' => '어떤 화면 찾는 거냥? 냥이가 바로 데려다주겠다냥.',
        'settings' =>
          '설정 탭에 있다냥. 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정까지 거기서 바꾸면 된다냥.',
        'todo_reset' =>
          '오늘 할 일은 매일 자정에 자동으로 초기화된다냥. 초기화 시간을 따로 조절하는 기능은 지금은 없다냥.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있다냥. 바로 열어주겠다냥.',
        'repeat_schedule' =>
          '반복 일정은 캘린더에서 만든다냥. 캘린더 일정을 입력하고 시계 버튼을 누른 다음 반복을 고르면 된다냥.',
        'repeat_schedule_delete' =>
          '반복 일정은 캘린더에서 해당 일정을 누르고 삭제하기를 누르면 된다냥. 반복으로 등록된 같은 일정이 같이 삭제된다냥.',
        'repeat_schedule_edit' =>
          '반복 일정 수정은 캘린더에서 해당 일정을 눌러서 하면 된다냥. 바로 캘린더로 데려다주겠다냥.',
        _ => base(' 화면으로 바로 데려다주겠다냥.'),
      },
      'boyfriend' => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 그 항목을 오른쪽으로 끝까지 밀면 완료야.',
        'picker' => '어디 찾는지 말해줘. 내가 바로 데려다줄게.',
        'settings' => '설정 탭에 있어. 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정까지 거기서 바꾸면 돼.',
        'todo_reset' => '오늘 할 일은 매일 자정에 자동으로 초기화돼. 초기화 시간은 따로 바꿀 수 없어.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있어. 내가 바로 열어줄게.',
        'repeat_schedule' =>
          '반복 일정은 캘린더에서 만들면 돼. 캘린더 일정 입력하고 시계 버튼 누른 다음 반복을 고르면 돼.',
        'repeat_schedule_delete' =>
          '반복 일정은 캘린더에서 해당 일정을 누르고 삭제하기를 누르면 돼. 반복으로 등록된 같은 일정이 같이 삭제돼.',
        'repeat_schedule_edit' => '반복 일정 수정은 캘린더에서 해당 일정을 눌러서 하면 돼. 바로 열어줄게.',
        _ => base(' 화면에 있어. 바로 열어줄게.'),
      },
      'halmae' => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 그 항목을 오른쪽으로 끝까지 밀면 완료다.',
        'picker' => '뭘 찾는 게냐, 우리 새끼. 할미가 바로 데려다주마.',
        'settings' =>
          '설정 탭에 있다, 우리 새끼. 모닝콜이랑 알람, 위젯, 채팅 배경, 비서 학습 설정 다 거기서 바꾸면 된다.',
        'todo_reset' =>
          '오늘 할 일은 매일 자정에 자동으로 초기화된다, 우리 새끼. 초기화 시간은 따로 바꾸는 기능이 없다.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있다. 할미가 바로 열어주마.',
        'repeat_schedule' =>
          '반복 일정은 캘린더에서 만든다, 우리 새끼. 캘린더 일정 적고 시계 버튼 누른 다음 반복을 고르면 된다.',
        'repeat_schedule_delete' =>
          '반복 일정은 캘린더에서 그 일정을 누르고 삭제하기를 누르면 된다. 반복으로 등록된 같은 일정이 같이 지워진다.',
        'repeat_schedule_edit' =>
          '반복 일정 수정은 캘린더에서 그 일정을 눌러서 하면 된다. 할미가 바로 열어주마.',
        _ => base(' 화면에 있다. 할미가 바로 열어주마.'),
      },
      'bro' => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 그 항목 오른쪽으로 끝까지 밀어라. 그러면 완료다.',
        'picker' => '어디 찾냐. 말만 해라, 바로 보내준다.',
        'settings' => '설정 탭이다. 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정 다 거기서 바꾸면 된다.',
        'todo_reset' => '오늘 할 일은 매일 자정에 자동 초기화된다. 초기화 시간은 따로 못 바꾼다.',
        'vision' => '장기 비전은 목표 화면 아래쪽이다. 바로 열어준다.',
        'repeat_schedule' =>
          '반복 일정은 캘린더에서 만든다. 캘린더 일정 입력하고 시계 버튼 누른 다음 반복을 고르면 된다.',
        'repeat_schedule_delete' =>
          '반복 일정은 캘린더에서 해당 일정 누르고 삭제하기 누르면 된다. 반복으로 등록된 같은 일정이 같이 삭제된다.',
        'repeat_schedule_edit' => '반복 일정 수정은 캘린더에서 해당 일정 눌러서 하면 된다. 바로 열어준다.',
        _ => base(' 화면이다. 바로 열어준다.'),
      },
      'nyang_halbae' => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 그 항목을 오른쪽으로 끝까지 밀면 완료다냥.',
        'picker' => '대표님, 찾으시는 화면을 선택해 주시면 바로 이동하겠습니다.',
        'settings' =>
          '대표님, 설정 탭에서 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정을 변경하실 수 있습니다.',
        'todo_reset' =>
          '대표님, 오늘 할 일은 매일 자정에 자동으로 초기화됩니다. 초기화 시간을 별도로 조절하는 기능은 현재 제공하지 않습니다.',
        'vision' => '대표님, 장기 비전은 목표 화면 하단에서 확인하실 수 있습니다. 바로 이동하겠습니다.',
        'repeat_schedule' =>
          '대표님, 반복 일정은 캘린더에서 생성하실 수 있습니다. 캘린더 일정을 입력한 뒤 시계 버튼을 누르고 반복을 선택해 주세요.',
        'repeat_schedule_delete' =>
          '대표님, 반복 일정은 캘린더에서 해당 일정을 누른 뒤 삭제하기를 선택하시면 됩니다. 반복으로 등록된 같은 일정이 함께 삭제됩니다.',
        'repeat_schedule_edit' =>
          '대표님, 반복 일정 수정은 캘린더에서 해당 일정을 선택해 진행하실 수 있습니다. 바로 이동하겠습니다.',
        _ => '대표님, ${base(' 화면으로 바로 이동하겠습니다.')}',
      },
      'sec_female' => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 해당 항목을 오른쪽으로 끝까지 밀면 완료돼요.',
        'picker' => '대표님, 어떤 화면을 찾으세요? 제가 바로 열어드릴게요.',
        'settings' => '대표님, 설정 탭에서 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정을 바꿀 수 있어요.',
        'todo_reset' =>
          '대표님, 오늘 할 일은 매일 자정에 자동으로 초기화돼요. 초기화 시간을 따로 조절하는 기능은 현재 없어요.',
        'vision' => '대표님, 장기 비전은 목표 화면 아래쪽에 있어요. 바로 열어드릴게요.',
        'repeat_schedule' =>
          '대표님, 반복 일정은 캘린더에서 만들 수 있어요. 캘린더 일정을 입력한 뒤 시계 버튼을 누르고 반복을 선택해 주세요.',
        'repeat_schedule_delete' =>
          '대표님, 반복 일정은 캘린더에서 해당 일정을 누른 뒤 삭제하기를 선택하면 돼요. 반복으로 등록된 같은 일정이 함께 삭제돼요.',
        'repeat_schedule_edit' =>
          '대표님, 반복 일정 수정은 캘린더에서 해당 일정을 선택해 진행할 수 있어요. 바로 이동할게요.',
        _ => '대표님, ${base(' 화면으로 바로 이동할게요.')}',
      },
      _ => switch (location) {
        'task_check' => '할 일 탭 > 오늘에서 그 항목을 오른쪽으로 끝까지 밀면 완료다냥.',
        'picker' => '어떤 화면을 찾고 있어? 바로 열어줄게.',
        'settings' => '설정 탭에서 모닝콜, 캘린더 알람, 위젯, 채팅 배경, 비서 학습 설정을 바꿀 수 있어.',
        'todo_reset' => '오늘 할 일은 매일 자정에 자동으로 초기화돼. 초기화 시간은 따로 바꿀 수 없어.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있어. 바로 열어줄게.',
        'repeat_schedule' =>
          '반복 일정은 캘린더에서 만들 수 있어. 캘린더 일정을 입력하고 시계 버튼을 누른 다음 반복을 선택하면 돼.',
        'repeat_schedule_delete' =>
          '반복 일정은 캘린더에서 해당 일정을 누르고 삭제하기를 선택하면 돼. 반복으로 등록된 같은 일정이 함께 삭제돼.',
        'repeat_schedule_edit' => '반복 일정 수정은 캘린더에서 해당 일정을 눌러서 하면 돼. 바로 열어줄게.',
        _ => base(' 화면에 있어. 바로 열어줄게.'),
      },
    };
  }
}
