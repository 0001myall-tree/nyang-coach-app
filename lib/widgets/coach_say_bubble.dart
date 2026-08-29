import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 어느 화면 위에든 뜨는 코치 말풍선.
///
/// 할 일 창을 열어둔 사람에게 채팅으로만 말을 걸면 그 말은 도착하지 않는다.
/// 화면 맨 위 겹치는 자리에 그리면 무엇이 열려 있든 그 위에 뜬다.
///
/// 스스로 사라지지 않는다. 계획을 쓰는 데 집중한 사람은 몇 초짜리 말풍선을
/// 그대로 놓친다. 닫는 것은 손으로 하고, 닫아도 같은 말이 채팅에 남아 있다.
class CoachSayBubble extends StatefulWidget {
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.accent.withValues(alpha: 0.35),
                ),
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
                  Row(
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
                        child: Text(
                          widget.text,
                          // 긴 말은 잘라둔다. 전문은 채팅에 그대로 남아 있다.
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13.5,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                      ),
                    ],
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
                          label: '알아서 할게',
                          onTap: widget.onDecline,
                          background: const Color(0xFFF3F2F7),
                          foreground: const Color(0xFF8A8698),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BubbleButton(
                          label: '그렇게 해볼게',
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
          borderRadius: BorderRadius.circular(10),
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
