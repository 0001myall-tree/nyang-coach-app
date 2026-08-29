import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_design_tokens.dart';

/// 어느 화면 위에든 뜨는 코치 말풍선.
///
/// 할 일 창을 열어둔 사람에게 채팅으로만 말을 걸면 그 말은 도착하지 않는다.
/// 화면 맨 위 겹치는 자리에 그리면 무엇이 열려 있든 그 위에 뜬다.
///
/// 스스로 사라지지 않는다. 계획을 쓰는 데 집중한 사람은 몇 초짜리 말풍선을
/// 그대로 놓친다. 닫는 것은 손으로 하고, 닫아도 같은 말이 채팅에 남아 있다.
class CoachSayBubble extends StatefulWidget {
  /// 버튼에 적힌 말. 누른 것을 기록에 남기는 쪽도 이 말을 쓴다.
  static const String acceptLabel = '그렇게 해볼게';
  static const String declineLabel = '알아서 할게';

  const CoachSayBubble({
    super.key,
    required this.text,
    required this.accent,
    required this.avatarAsset,
    required this.onAccept,
    required this.onDecline,
  });

  final String text;
  final Color accent;

  /// 코치 얼굴. 누가 말하는지 한눈에 보여야 한다.
  final String avatarAsset;

  /// 이야기해보겠다고 했다. 그 코치 채팅으로 데려간다.
  final VoidCallback onAccept;

  /// 지금은 됐다고 했다. 한동안 말을 걸지 않는다.
  final VoidCallback onDecline;

  @override
  State<CoachSayBubble> createState() => _CoachSayBubbleState();
}

class _CoachSayBubbleState extends State<CoachSayBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 말풍선이 차지할 수 있는 최대 높이. 화면의 이만큼.
  ///
  /// 길이를 고정하지 않는다. 한 줄짜리 말에 큰 상자가 뜨면 어색하고, 긴 말이
  /// 잘리면 정작 뒷문장이 안 보인다. 대신 상한을 둔다 — 코치가 길게 쓴 날
  /// 말풍선이 화면을 덮으면 그 아래 할 일이 아예 안 보인다.
  static const double _maxHeightRatio = 0.4;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.padding.bottom;
    final maxHeight = media.size.height * _maxHeightRatio;

    return Positioned(
      // 탭바 위에 앉힌다. 할 일 목록을 덜 가리는 자리다.
      left: 12,
      right: 12,
      bottom: bottom + 84,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppDesignTokens.surface,
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusMedium,
                ),
                border: Border.all(color: AppDesignTokens.brandBorder),
                // 그림자만 확인 카드보다 진하다. 이건 다른 화면 위에 떠 있는
                // 것이라, 같은 값으로 두면 할 일 목록에 파묻힌다.
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipOval(
                          child: Image.asset(
                            widget.avatarAsset,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 34,
                              height: 34,
                              color: widget.accent.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          // 상한에 닿으면 잘리는 대신 그 안에서 스크롤된다.
                          child: SingleChildScrollView(
                            child: Text(
                              widget.text,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13.5,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 답을 두 개로 갈라둔다.
                  //
                  // 닫기(X)만 있던 때는 말없이 사라지는 것이 유일한 답이었고,
                  // 앱은 그 침묵을 세어 "듣기 싫은가 보다"라고 짐작해야 했다.
                  // 물어보면 짐작할 일이 없다.
                  Row(
                    children: [
                      Expanded(
                        child: _BubbleButton(
                          label: CoachSayBubble.declineLabel,
                          onTap: widget.onDecline,
                          background: AppDesignTokens.surfaceSubtle,
                          foreground: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BubbleButton(
                          label: CoachSayBubble.acceptLabel,
                          onTap: widget.onAccept,
                          background: widget.accent,
                          foreground: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleButton extends StatelessWidget {
  const _BubbleButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusSmall),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// 코치가 말을 지어내는 동안 그 자리에 먼저 뜨는 것.
///
/// 핵심을 지정하고 몇 초 뒤에 말풍선이 떠서, 그때는 이미 다른 것을 보고 있는
/// 일이 잦았다. 뜰 자리를 미리 잡아두면 무언가 오는 중인 줄 알고 기다릴 수
/// 있다. 말풍선과 같은 자리, 같은 모양이라 답이 도착하면 그대로 바뀐다.
///
/// 누를 것은 없다. 기다리는 일에 손댈 것을 주면 그 자체가 일이 된다.
class CoachThinkingBubble extends StatefulWidget {
  const CoachThinkingBubble({
    super.key,
    required this.accent,
    required this.avatarAsset,
  });

  final Color accent;
  final String avatarAsset;

  @override
  State<CoachThinkingBubble> createState() => _CoachThinkingBubbleState();
}

class _CoachThinkingBubbleState extends State<CoachThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom + 84,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
            border: Border.all(color: AppDesignTokens.brandBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  widget.avatarAsset,
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 34,
                    height: 34,
                    color: widget.accent.withValues(alpha: 0.15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 점 세 개가 차례로 밝아진다. 글자로 "생각 중"이라고 적으면
              // 그것도 읽어야 할 말이 된다.
              AnimatedBuilder(
                animation: _anim,
                builder: (_, _) => Row(
                  children: List.generate(3, (i) {
                    final t = (_anim.value * 3 - i).clamp(0.0, 1.0);
                    final glow = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.accent.withValues(
                            alpha: 0.25 + glow * 0.6,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
