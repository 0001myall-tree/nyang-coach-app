class _MilestoneMemoDialogState extends State<MilestoneMemoDialog> {
  // --- Phase 1: 다중 섹션 데이터 및 컨트롤러 ---
  List<MemoSection> _sections = [];
  final List<TextEditingController> _titleCtrls = [];
  final List<TextEditingController> _contentCtrls = [];
  final List<FocusNode> _titleFocusNodes = [];
  final List<FocusNode> _contentFocusNodes = [];

  // --- Phase 2: 실행 아이템 데이터 및 컨트롤러 ---
  List<ActionCandidate> _actions = [];
  final List<TextEditingController> _actionCtrls = [];
  final List<FocusNode> _actionFocusNodes = [];

  TextEditingController? _focusedCtrl;
  TextSelection _baseSelection = const TextSelection.collapsed(offset: 0);
  String _baseText = '';

  // --- 음성 인식 ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  
  @override
  void initState() {
    super.initState();
    _migrateAndInitData();
    _initSpeech();
  }

  void _migrateAndInitData() {
    // 1. Sections
    if (widget.milestone.memoSections != null &&
        widget.milestone.memoSections!.isNotEmpty) {
      _sections = List.from(widget.milestone.memoSections!);
    } else {
      String oldMemo = widget.milestone.memo ?? '';
      if (oldMemo.trim().isNotEmpty) {
        _sections.add(MemoSection(title: '기본 메모', content: oldMemo));
      } else {
        _sections.add(MemoSection(title: '', content: ''));
      }
    }

    for (var section in _sections) {
      _addSectionControllers(section.title, section.content);
    }

    // 2. Actions
    if (widget.milestone.actionCandidates != null) {
      _actions = List.from(widget.milestone.actionCandidates!);
    }
    for (var action in _actions) {
      _addActionControllers(action.title);
    }
  }

  void _updateFocus(TextEditingController ctrl, FocusNode node) {
    if (node.hasFocus) {
      _focusedCtrl = ctrl;
      if (mounted) setState(() {});
    }
  }

  void _addSectionControllers(String title, String content) {
    final tCtrl = TextEditingController(text: title);
    final cCtrl = TextEditingController(text: content);
    final tNode = FocusNode();
    final cNode = FocusNode();

    tNode.addListener(() => _updateFocus(tCtrl, tNode));
    cNode.addListener(() => _updateFocus(cCtrl, cNode));

    _titleCtrls.add(tCtrl);
    _contentCtrls.add(cCtrl);
    _titleFocusNodes.add(tNode);
    _contentFocusNodes.add(cNode);
  }

  void _addActionControllers(String title) {
    final aCtrl = TextEditingController(text: title);
    final aNode = FocusNode();

    aNode.addListener(() => _updateFocus(aCtrl, aNode));

    _actionCtrls.add(aCtrl);
    _actionFocusNodes.add(aNode);
  }

  void _addNewSection() {
    setState(() {
      _sections.add(MemoSection(title: '', content: ''));
      _addSectionControllers('', '');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNodes.last.requestFocus();
    });
  }

  void _removeSection(int index) async {
    final confirm = await _showConfirmDeleteDialog('메모 삭제', '이 메모를 정말 삭제하시겠습니까?');
    if (!confirm) return;
    setState(() {
      _sections.removeAt(index);
      _titleCtrls[index].dispose();
      _contentCtrls[index].dispose();
      _titleFocusNodes[index].dispose();
      _contentFocusNodes[index].dispose();
      _titleCtrls.removeAt(index);
      _contentCtrls.removeAt(index);
      _titleFocusNodes.removeAt(index);
      _contentFocusNodes.removeAt(index);

      if (_sections.isEmpty) {
        _addNewSection();
      }
    });
  }

  void _addNewAction() {
    setState(() {
      _actions.add(ActionCandidate(id: DateTime.now().millisecondsSinceEpoch.toString(), title: ''));
      _addActionControllers('');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _actionFocusNodes.last.requestFocus();
    });
  }

  void _removeAction(int index) async {
    final confirm = await _showConfirmDeleteDialog('실행 아이템 삭제', '이 실행 아이템을 정말 삭제하시겠습니까?');
    if (!confirm) return;
    setState(() {
      _actions.removeAt(index);
      _actionCtrls[index].dispose();
      _actionFocusNodes[index].dispose();
      _actionCtrls.removeAt(index);
      _actionFocusNodes.removeAt(index);
    });
  }

  // --- 음성 인식 로직 ---
  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint("Speech error: $error");
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('음성 인식 오류: ${error.errorMsg}')),
            );
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Speech init error: $e");
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      _initSpeech();
      return;
    }
    if (_focusedCtrl == null) {
      if (_contentFocusNodes.isNotEmpty) {
        _contentFocusNodes.first.requestFocus();
        _focusedCtrl = _contentCtrls.first;
      } else {
        return;
      }
    }

    _baseText = _focusedCtrl!.text;
    _baseSelection = _focusedCtrl!.selection;
    await _speechToText.listen(
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      onResult: (result) {
        if (mounted && _focusedCtrl != null) {
          setState(() {
            final spoken = result.recognizedWords;
            int start = _baseSelection.start;
            int end = _baseSelection.end;
            if (start < 0) {
              start = _baseText.length;
              end = _baseText.length;
            }
            final insertText = (_baseText.isNotEmpty &&
                    start > 0 &&
                    _baseText[start - 1] != ' '
                ? ' '
                : '') +
                spoken;
            _focusedCtrl!.text = _baseText.replaceRange(start, end, insertText);
            _focusedCtrl!.selection = TextSelection.collapsed(
              offset: start + insertText.length,
            );
          });
        }
      },
      localeId: 'ko_KR',
      cancelOnError: false,
      partialResults: true,
    );
    setState(() => _isListening = true);
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  // --- 저장 로직 ---
  void _saveDataAndClose() {
    // 1. Sections
    for (int i = 0; i < _sections.length; i++) {
      _sections[i].title = _titleCtrls[i].text.trim();
      _sections[i].content = _contentCtrls[i].text.trim();
    }
    _sections.removeWhere((s) => s.title.isEmpty && s.content.isEmpty);
    widget.milestone.memoSections = _sections;
    
    if (_sections.isNotEmpty) {
      widget.milestone.memo = _sections.first.content;
    } else {
      widget.milestone.memo = '';
    }

    // 2. Actions
    for (int i = 0; i < _actions.length; i++) {
      _actions[i].title = _actionCtrls[i].text.trim();
    }
    _actions.removeWhere((a) => a.title.isEmpty);
    widget.milestone.actionCandidates = _actions;

    widget.onSave('saved');
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _speechToText.stop();
    for (var ctrl in _titleCtrls) ctrl.dispose();
    for (var ctrl in _contentCtrls) ctrl.dispose();
    for (var node in _titleFocusNodes) node.dispose();
    for (var node in _contentFocusNodes) node.dispose();
    
    for (var ctrl in _actionCtrls) ctrl.dispose();
    for (var node in _actionFocusNodes) node.dispose();
    
    super.dispose();
  }

  // --- 위젯 빌드 ---
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.milestone.text.isNotEmpty
                            ? widget.milestone.text
                            : '마일스톤 메모',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3D3A4E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: Color(0xFF8B7CFF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.milestone.date ?? '기한 없음',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8B7CFF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _saveDataAndClose,
                  child: const Icon(
                    Icons.close,
                    color: Color(0xFFA0A0B0),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          
          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Sections ---
                  ...List.generate(_sections.length, (index) => _buildSectionCard(index)),
                  
                  GestureDetector(
                    onTap: _addNewSection,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF8B7CFF).withOpacity(0.3)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 16, color: Color(0xFF8B7CFF)),
                          const SizedBox(width: 4),
                          Text(
                            '섹션 추가',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8B7CFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(color: Color(0xFFE5E7EB), height: 32, thickness: 1),

                  // --- Action Items ---
                  Row(
                    children: [
                      const Text(
                        '⚡️',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '실행 아이템 (행동 후보)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  ...List.generate(_actions.length, (index) => _buildActionCard(index)),

                  GestureDetector(
                    onTap: _addNewAction,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 40),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 16, color: Color(0xFF6B7280)),
                          const SizedBox(width: 6),
                          Text(
                            '실행 아이템 추가',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                )
              ],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isListening) {
                      _stopListening();
                    } else {
                      _startListening();
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red.withOpacity(0.1)
                          : const Color(0xFFF5F3FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 20,
                      color: _isListening
                          ? Colors.red
                          : const Color(0xFF8B7CFF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isListening ? '말씀하세요. 듣고 있습니다...' : '음성으로 내용을 입력해보세요!',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: _isListening ? Colors.red : const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _saveDataAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.coach.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '저장',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrls[index],
                  focusNode: _titleFocusNodes[index],
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3D3A4E),
                  ),
                  decoration: InputDecoration(
                    hintText: '섹션 제목 (예: 성장 고민)',
                    hintStyle: GoogleFonts.notoSansKr(
                      color: const Color(0xFFA0A0B0),
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _removeSection(index),
                child: const Icon(Icons.close, size: 16, color: Color(0xFFA0A0B0)),
              ),
            ],
          ),
          const Divider(color: Color(0xFFE5E7EB), height: 20),
          TextField(
            controller: _contentCtrls[index],
            focusNode: _contentFocusNodes[index],
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: const Color(0xFF3D3A4E),
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: '내용을 입력하세요...',
              hintStyle: GoogleFonts.notoSansKr(
                color: const Color(0xFFA0A0B0),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(int index) {
    final action = _actions[index];
    final isConverted = action.convertedTaskId != null || action.convertedHabitId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isConverted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isConverted ? const Color(0xFF10B981) : const Color(0xFFD1D5DB),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _actionCtrls[index],
              focusNode: _actionFocusNodes[index],
              enabled: !isConverted, // Disable editing if already converted
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: isConverted ? const Color(0xFF9CA3AF) : const Color(0xFF3D3A4E),
                decoration: isConverted ? TextDecoration.lineThrough : null,
              ),
              decoration: InputDecoration(
                hintText: '구체적인 행동 입력 (예: 개발 컨퍼런스 등록하기)',
                hintStyle: GoogleFonts.notoSansKr(
                  color: const Color(0xFFA0A0B0),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (!isConverted) ...[
            const SizedBox(width: 8),
            // Phase 3 Button Placeholder
            GestureDetector(
              onTap: () {
                // TODO: Phase 3 (Conversion Bottom Sheet)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('전환 기능은 Phase 3에서 활성화됩니다!')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  '전환',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _removeAction(index),
              child: const Icon(Icons.close, size: 16, color: Color(0xFFA0A0B0)),
            ),
          ],
        ],
      ),
    );
  }

  // --- CONFIRM DELETE DIALOG ---
  Future<bool> _showConfirmDeleteDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3D3A4E),
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            color: const Color(0xFF4B4A5D),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFA0A0B0),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제',
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE53E3E),
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }
}
