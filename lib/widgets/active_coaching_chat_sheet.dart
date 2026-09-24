/// 적극 코칭 카드에서 "하기 싫어"를 고른 뒤 할 일 창 위에 뜨는 작은 대화창.
///
/// 코치가 먼저 말을 건다. 카드에서 누른 버튼이 이미 사용자의 첫 마디라서,
/// 창을 열자마자 사용자에게 또 입력을 받으면 한 말을 두 번 하게 된다.
///
/// 창 아래에는 그 일을 바로 시작하는 버튼이 늘 떠 있다. 대화 중 어느 순간이든
/// 마음이 움직이면 그때 누르면 된다 — 코치가 "이제 시작해볼까?"라고 말해줄
/// 때까지 기다리게 하면, 그 사이에 마음이 다시 식는다.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/coach_config.dart';
import '../services/active_coaching_chat.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_font.dart';

/// 창이 닫히면서 남기는 답.
enum ActiveCoachingChatOutcome {
  /// 그 일을 시작하기로 했다.
  start,

  /// 그냥 닫았다.
  closed,
}

class ActiveCoachingChatSheet extends StatefulWidget {
  const ActiveCoachingChatSheet({super.key, required this.chat});

  final ActiveCoachingChat chat;

  /// 창을 띄우고, 닫힐 때의 답을 돌려준다.
  static Future<ActiveCoachingChatOutcome> show(
    BuildContext context,
    ActiveCoachingChat chat,
  ) async {
    final outcome = await showModalBottomSheet<ActiveCoachingChatOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActiveCoachingChatSheet(chat: chat),
    );
    return outcome ?? ActiveCoachingChatOutcome.closed;
  }

  @override
  State<ActiveCoachingChatSheet> createState() =>
      _ActiveCoachingChatSheetState();
}

class _ActiveCoachingChatSheetState extends State<ActiveCoachingChatSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _waiting = false;
  bool _failed = false;

  /// 지금 보여줄 고를 거리. 코치가 새로 말하면 바뀐다.
  List<String> _chips = const [];

  ActiveCoachingChat get _chat => widget.chat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send(_chat.openingLine));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _waiting) return;
    await _await(() => _chat.send(trimmed));
  }

  Future<void> _await(Future<ActiveCoachingChatReply?> Function() ask) async {
    setState(() {
      _waiting = true;
      _failed = false;
      _chips = const [];
    });
    _scrollToEnd();
    final reply = await ask();
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _failed = reply == null;
      _chips = reply?.chips ?? const [];
    });
    _scrollToEnd();
  }

  void _submitInput() {
    final text = _input.text;
    _input.clear();
    _send(text);
  }

  /// 고를 거리를 눌렀을 때. "기타"는 직접 쓰라는 뜻이라 입력칸으로 보낸다.
  void _tapChip(String chip) {
    if (chip == '기타') {
      _inputFocus.requestFocus();
      return;
    }
    _send(chip);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final coach = CoachConfigs.get(_chat.coachId);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: media.size.height * 0.62,
        decoration: const BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _header(coach),
              const Divider(height: 1, color: AppDesignTokens.divider),
              Expanded(child: _messages()),
              if (_chips.isNotEmpty || _failed) _quickReplies(),
              _inputRow(),
              _startButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(CoachConfig coach) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
    child: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppDesignTokens.brandSoft,
          backgroundImage: AssetImage(coach.imagePath),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            coach.name,
            style: appFont(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: () =>
              Navigator.of(context).pop(ActiveCoachingChatOutcome.closed),
          icon: const Icon(Icons.close_rounded, color: AppDesignTokens.textMuted),
        ),
      ],
    ),
  );

  Widget _messages() => ListView(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    children: [
      for (final line in _chat.lines) _bubble(line.text, isUser: line.isUser),
      if (_waiting)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        ),
    ],
  );

  Widget _bubble(String text, {required bool isUser}) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.74,
      ),
      decoration: BoxDecoration(
        color: isUser ? AppDesignTokens.brand : AppDesignTokens.brandSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: appFont(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: isUser ? Colors.white : AppDesignTokens.textPrimary,
        ),
      ),
    ),
  );

  /// 코치가 내민 고를 거리. 답을 못 받아왔으면 다시 묻는 버튼 하나.
  Widget _quickReplies() {
    final labels = _failed ? const ['다시 물어볼게'] : _chips;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(
          child: GestureDetector(
            onTap: _failed ? _retry : () => _tapChip(labels[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppDesignTokens.brandChip,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppDesignTokens.brandBorder),
              ),
              // 채팅방 빠른 답장과 같은 손글씨체. 누르면 내 말이 된다.
              child: Text(
                labels[i],
                style: GoogleFonts.gaegu(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.brandPressed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 답을 못 받아온 턴을 다시 묻는다. 사용자의 말은 이미 적혀 있다.
  void _retry() {
    if (_waiting) return;
    _await(_chat.retry);
  }

  Widget _inputRow() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 10, 4),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            enabled: !_waiting,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submitInput(),
            style: appFont(fontSize: 14, color: AppDesignTokens.textPrimary),
            decoration: InputDecoration(
              hintText: '하고 싶은 말',
              hintStyle: appFont(fontSize: 14, color: AppDesignTokens.textMuted),
              isDense: true,
              filled: true,
              fillColor: AppDesignTokens.surfaceSubtle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _waiting ? null : _submitInput,
          icon: const Icon(Icons.send_rounded, color: AppDesignTokens.brand),
        ),
      ],
    ),
  );

  Widget _startButton() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppDesignTokens.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: () =>
            Navigator.of(context).pop(ActiveCoachingChatOutcome.start),
        child: Text(
          "'${_shorten(_chat.taskName)}' 지금 시작",
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );

  static String _shorten(String name) =>
      name.length <= 14 ? name : '${name.substring(0, 14)}…';
}
