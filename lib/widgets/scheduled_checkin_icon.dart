import 'package:flutter/material.dart';

/// 시간 지정형 선제 체크인 알림 아이콘 (편지 아이콘 + 깜빡이는 빨간 점).
/// 코치선택 화면, 프렌즈 코치 채팅 화면 양쪽에서 재사용한다.
class ScheduledCheckInIcon extends StatefulWidget {
  final VoidCallback onTap;
  final Color iconColor;

  const ScheduledCheckInIcon({
    super.key,
    required this.onTap,
    this.iconColor = const Color(0xFF6B5EA8),
  });

  @override
  State<ScheduledCheckInIcon> createState() => _ScheduledCheckInIconState();
}

class _ScheduledCheckInIconState extends State<ScheduledCheckInIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.mail_outline_rounded, color: widget.iconColor, size: 24),
            Positioned(
              top: -2,
              right: -2,
              child: FadeTransition(
                opacity: _ctrl,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4D4F),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
