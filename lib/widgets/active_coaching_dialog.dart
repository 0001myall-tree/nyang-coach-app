/// 적극 코칭이 "못 했어"를 받은 뒤 이어지는 팝업.
///
/// 할 일 창 위에 뜬다. 화면을 다 덮지 않아서 뒤에 그 일이 계속 보이고, 여기서
/// 고르면 그 칸이 바로 돌아간다. 채팅으로 데려가지 않는 이유가 그것이다 —
/// 거기서 마음먹은 사람은 할 일 창으로 다시 건너와야 하는데, 이 앱은 그 한 칸이
/// 안 하게 되는 이유가 된다고 보고 여러 군데서 없애왔다.
///
/// 단계는 넷이고, 앞 단계의 답이 다음 단계를 정한다.
///
/// ```
/// 왜 못 했어?  →  지금 뭘 해볼까?  →  그럼 지금 할 수 있는 건?  →  몇 시부터?
/// ```
///
/// **시간부터 묻지 않는다.** 그러면 앱이 스누즈 기계가 된다 — 4시로 미루고,
/// 4시에 또 못 하고, 또 미루고. 왜 못 하는지 모르니 매번 같은 말만 하게 되고,
/// 무엇보다 묻자마자 빠져나갈 문을 열어주는 셈이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/active_coaching_move.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_font.dart';
import 'banner_answer_dialog.dart';

/// 팝업이 닫히면서 남기는 답.
enum ActiveCoachingOutcomeKind {
  /// 바깥을 눌러 닫았다. 아무 일도 없었다.
  dismissed,

  /// 한 수를 골랐다. 그 일을 지금 시작한다.
  start,

  /// 몇 시에 하겠다고 정했다.
  promise,

  /// 버튼에 없는 시각을 직접 고르겠다고 했다.
  chooseTime,
}

class ActiveCoachingOutcome {
  const ActiveCoachingOutcome(
    this.kind, {
    this.taskName,
    this.move,
    this.reason,
    this.promisedAt,
  });

  final ActiveCoachingOutcomeKind kind;

  /// 실제로 다루게 된 일. 목록에서 다른 것을 골랐으면 그쪽 이름이다.
  final String? taskName;

  /// 고른 한 수.
  final String? move;

  /// 사용자가 고른 "왜 못 했는지".
  final String? reason;

  final DateTime? promisedAt;
}

/// 목록에 보여줄 남은 일 하나.
class ActiveCoachingChoice {
  const ActiveCoachingChoice({required this.name, this.timeLabel});

  final String name;

  /// "오후 8:00". 아직 시각이 안 된 일도 보여주되 언제인지는 적어준다.
  final String? timeLabel;
}

/// 사용자가 고르는 "왜 못 했는지".
///
/// 이유가 다음 한 수를 가른다. 머리가 안 돌아가는 사람에게는 손댈 자리를
/// 만들어주면 되고, 자리가 아닌 사람에게는 무엇을 해줘도 소용없다.
class ActiveCoachingReason {
  const ActiveCoachingReason(this.label, this.icon, {this.blocksNow = false});

  final String label;
  final String icon;

  /// 지금 그 자리가 아니라는 뜻인지. 그러면 한 수를 물을 자리도 아니다.
  final bool blocksNow;

  static const List<ActiveCoachingReason> all = [
    ActiveCoachingReason('머리가 안 돌아가', 'fa-lightbulb-solid'),
    ActiveCoachingReason('부담돼서', 'heart-pulse'),
    ActiveCoachingReason('지금은 시간이 안 나', 'fa-clock-regular', blocksNow: true),
  ];
}

class ActiveCoachingDialog extends StatefulWidget {
  const ActiveCoachingDialog({
    super.key,
    required this.taskName,
    required this.askMoves,
    required this.timeChoices,
    this.otherTasks = const [],
  });

  /// 처음 말을 건 일.
  final String taskName;

  /// 한 수를 받아오는 길. [names]가 하나면 그 일로 고정이고, 여럿이면 고르는
  /// 것까지 맡긴다.
  final Future<ActiveCoachingMoves?> Function(
    List<String> names,
    String? reason,
  )
  askMoves;

  /// 갈아탈 수 있는 남은 일들.
  final List<ActiveCoachingChoice> otherTasks;

  /// 미룰 수 있는 시각들. 밤이라 남는 자리가 없으면 비어 있다.
  final List<DateTime> timeChoices;

  @override
  State<ActiveCoachingDialog> createState() => _ActiveCoachingDialogState();
}

enum _Step { reason, moves, pickAnother, time }

class _ActiveCoachingDialogState extends State<ActiveCoachingDialog> {
  _Step _step = _Step.reason;
  String? _reason;
  late String _task = widget.taskName;
  List<String> _moves = const [];
  bool _asking = false;

  /// 이미 다른 일로 갈아탔는지.
  ///
  /// 한 개입 안에서 갈아타기는 한 번까지다. 두 번 넘어가면 "그럼 이건?"을
  /// 반복하는 심문이 된다.
  bool _switched = false;

  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    return AnswerDialogShell(children: _children());
  }

  List<Widget> _children() => switch (_step) {
    _Step.reason => _reasonStep(),
    _Step.moves => _movesStep(),
    _Step.pickAnother => _pickAnotherStep(),
    _Step.time => _timeStep(),
  };

  // ── 왜 못 했어? ────────────────────────────────────────

  List<Widget> _reasonStep() => [
    AnswerDialogQuestion("'${_shorten(_task)}' 아직이네.\n왜 못 했어?"),
    const SizedBox(height: 16),
    for (var i = 0; i < ActiveCoachingReason.all.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      AnswerChoiceButton(
        label: ActiveCoachingReason.all[i].label,
        icon: ActiveCoachingReason.all[i].icon,
        onTap: () => _answerReason(ActiveCoachingReason.all[i]),
      ),
    ],
  ];

  void _answerReason(ActiveCoachingReason reason) {
    setState(() => _reason = reason.label);
    // 자리가 아니라는 사람에게 "지금 이거 해볼까"는 통하지 않는다. 그 사람에게
    // 필요한 것은 언제 할지 정하는 쪽이다.
    if (reason.blocksNow) {
      _goToTime();
      return;
    }
    _askMoves([_task]);
  }

  // ── 지금 뭘 해볼까? ────────────────────────────────────

  List<Widget> _movesStep() => [
    AnswerDialogQuestion("'${_shorten(_task)}'\n지금 뭘 해볼까?"),
    const SizedBox(height: 16),
    if (_asking)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      )
    else ...[
      for (var i = 0; i < _moves.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        AnswerChoiceButton(
          label: _moves[i],
          icon: 'fa-circle-play-solid',
          isPrimary: i == 0,
          onTap: () => _close(
            ActiveCoachingOutcome(
              ActiveCoachingOutcomeKind.start,
              taskName: _task,
              move: _moves[i],
              reason: _reason,
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      AnswerChoiceButton(
        label: _moves.length > 1 ? '지금은 둘 다 안 돼' : '지금은 안 되겠어',
        icon: 'fa-clock-regular',
        onTap: _afterMovesRefused,
      ),
    ],
  ];

  Future<void> _askMoves(List<String> names) async {
    setState(() {
      _step = _Step.moves;
      _asking = true;
      _moves = const [];
    });
    final result = await widget.askMoves(names, _reason);
    if (!mounted) return;
    // 한 수를 못 받아왔다. 한도가 찼거나 통신이 끊긴 경우인데, 그렇다고 팝업이
    // 그냥 닫히면 사용자는 아무것도 못 고른 채 끝난다. 다음 자리로 넘긴다.
    if (result == null || result.moves.isEmpty) {
      _afterMovesRefused();
      return;
    }
    setState(() {
      _asking = false;
      _task = result.task;
      _moves = result.moves;
    });
  }

  /// 한 수를 받아들이지 않았을 때.
  ///
  /// 아직 갈아타지 않았고 남은 일이 있으면 그쪽을 먼저 묻는다. "지금 조금이라도
  /// 할 수 있는 것"을 찾는 쪽이, 몇 시에 할지 정하는 쪽보다 먼저다.
  void _afterMovesRefused() {
    if (!_switched && widget.otherTasks.isNotEmpty) {
      setState(() {
        _asking = false;
        _step = _Step.pickAnother;
      });
      return;
    }
    _goToTime();
  }

  // ── 그럼 지금 할 수 있는 건? ───────────────────────────

  List<Widget> _pickAnotherStep() => [
    const AnswerDialogQuestion(
      '그럼 지금 조금이라도 할 수 있는 건 뭐야?\n여러 개 골라도 돼. 그중에 하나 골라줄게.',
    ),
    const SizedBox(height: 14),
    for (final choice in widget.otherTasks) ...[
      _ChoiceRow(
        label: choice.name,
        trailing: choice.timeLabel,
        checked: _picked.contains(choice.name),
        onTap: () => setState(() {
          if (!_picked.remove(choice.name)) _picked.add(choice.name);
        }),
      ),
      const SizedBox(height: 6),
    ],
    const SizedBox(height: 10),
    AnswerChoiceButton(
      // 아무것도 안 고른 것과 "모르겠어"는 같은 말이다. 둘 다 남은 일 전부를
      // 넘기고 그중에서 코치가 고른다.
      label: _picked.isEmpty ? '모르겠어, 골라줘' : '이걸로',
      icon: _picked.isEmpty ? 'fa-lightbulb-solid' : 'fa-circle-play-solid',
      isPrimary: true,
      onTap: () {
        _switched = true;
        _askMoves(
          _picked.isEmpty
              ? widget.otherTasks
                    .map((choice) => choice.name)
                    .toList(growable: false)
              : _picked.toList(growable: false),
        );
      },
    ),
  ];

  // ── 몇 시부터? ─────────────────────────────────────────

  void _goToTime() => setState(() {
    _asking = false;
    _step = _Step.time;
  });

  List<Widget> _timeStep() => [
    AnswerDialogQuestion(
      widget.timeChoices.isEmpty
          ? "'${_shorten(_task)}'\n오늘은 여기까지 할까?"
          : "'${_shorten(_task)}'\n몇 시부터 할까?",
    ),
    const SizedBox(height: 16),
    for (var i = 0; i < widget.timeChoices.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      AnswerChoiceButton(
        label: _clock(widget.timeChoices[i]),
        icon: 'fa-clock-regular',
        isPrimary: i == 0,
        onTap: () => _close(
          ActiveCoachingOutcome(
            ActiveCoachingOutcomeKind.promise,
            taskName: _task,
            reason: _reason,
            promisedAt: widget.timeChoices[i],
          ),
        ),
      ),
    ],
    if (widget.timeChoices.isNotEmpty) const SizedBox(height: 8),
    AnswerChoiceButton(
      label: '직접 고르기',
      icon: 'planner-clock',
      isPrimary: widget.timeChoices.isEmpty,
      onTap: () => _close(
        ActiveCoachingOutcome(
          ActiveCoachingOutcomeKind.chooseTime,
          taskName: _task,
          reason: _reason,
        ),
      ),
    ),
  ];

  // ── 공통 ───────────────────────────────────────────────

  void _close(ActiveCoachingOutcome outcome) {
    Navigator.of(context).pop(outcome);
  }

  /// 팝업 한 줄에 들어가는 길이. 넘치면 질문이 세 줄이 된다.
  static const int _nameLimit = 14;

  static String _shorten(String name) =>
      name.length <= _nameLimit ? name : '${name.substring(0, _nameLimit)}…';

  /// "3:30".
  ///
  /// 상대 표현을 쓰지 않는다. 3시 12분에 "30분 뒤 · 3:30"은 18분 뒤라 거짓말이
  /// 된다. 지금 폰을 보고 있는 사람이라 몇 시인지 안다.
  static String _clock(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '$hour:${at.minute.toString().padLeft(2, '0')}';
  }
}

/// 목록에서 고르는 줄 하나.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.checked,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String? trailing;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked ? AppDesignTokens.brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked
                ? AppDesignTokens.brand
                : AppDesignTokens.brandBorder,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/circle-check.svg',
              width: 15,
              height: 15,
              colorFilter: ColorFilter.mode(
                checked ? AppDesignTokens.brand : const Color(0xFFCFCADD),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                style: appFont(
                  fontSize: 14,
                  fontWeight: checked ? FontWeight.w800 : FontWeight.w600,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Text(
                trailing!,
                style: appFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A96A8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
