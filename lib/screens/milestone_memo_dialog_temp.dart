class _MilestoneMemoDialogState extends State<MilestoneMemoDialog> {
  // --- Phase 1: 다중 섹션 데이터 및 컨트롤러 ---
  List<MemoSection> _sections = [];
  final List<TextEditingController> _titleCtrls = [];
  final List<TextEditingController> _contentCtrls = [];
  final List<FocusNode> _titleFocusNodes = [];
  final List<FocusNode> _contentFocusNodes = [];

  TextEditingController? _focusedCtrl;
  TextSelection _baseSelection = const TextSelection.collapsed(offset: 0);
  String _baseText = '';

  // --- 음성 인식 ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  
  bool _isEditingGlobal = true;

  @override
  void initState() {
    super.initState();
    _migrateAndInitData();
    _initSpeech();
  }

  void _migrateAndInitData() {
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
      _addControllers(section.title, section.content);
    }
  }

  void _addControllers(String title, String content) {
    final tCtrl = TextEditingController(text: title);
    final cCtrl = TextEditingController(text: content);
    final tNode = FocusNode();
    final cNode = FocusNode();

    void updateFocus(TextEditingController ctrl, FocusNode node) {
      if (node.hasFocus) {
        _focusedCtrl = ctrl;
        if (mounted) setState(() {});
      }
    }

    tNode.addListener(() => updateFocus(tCtrl, tNode));
    cNode.addListener(() => updateFocus(cCtrl, cNode));

    _titleCtrls.add(tCtrl);
    _contentCtrls.add(cCtrl);
    _titleFocusNodes.add(tNode);
    _contentFocusNodes.add(cNode);
  }

  void _addNewSection() {
    setState(() {
      _sections.add(MemoSection(title: '', content: ''));
      _addControllers('', '');
    });
    // Request focus on the new section title
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNodes.last.requestFocus();
    });
  }

  void _removeSection(int index) {
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
      // 기본적으로 첫 번째 컨텐츠 필드에 포커스
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

  void _insertTextAtFocusedCtrl(String textToInsert) {
    if (_focusedCtrl == null) return;
    final currentText = _focusedCtrl!.text;
    final selection = _focusedCtrl!.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0) {
      start = currentText.length;
      end = currentText.length;
    }
    final newText = currentText.replaceRange(start, end, textToInsert);
    _focusedCtrl!.text = newText;
    _focusedCtrl!.selection = TextSelection.collapsed(
      offset: start + textToInsert.length,
    );
    setState(() {});
  }

  // --- 저장 로직 ---
  void _saveDataAndClose() {
    // Sync controllers to data model
    for (int i = 0; i < _sections.length; i++) {
      _sections[i].title = _titleCtrls[i].text.trim();
      _sections[i].content = _contentCtrls[i].text.trim();
    }
    // Remove completely empty sections
    _sections.removeWhere((s) => s.title.isEmpty && s.content.isEmpty);

    widget.milestone.memoSections = _sections;
    
    // For backward compatibility, keep the first section's content in memo if there's only 1?
    // Actually, onSave expects a string, but the parent uses widget.milestone directly.
    // Let's pass a dummy string to trigger rebuild, or just the JSON string.
    widget.onSave('saved');
    Navigator.pop(context);
  }

  // --- 위젯 빌드 ---
  @override
  void dispose() {
    _speechToText.stop();
    for (var ctrl in _titleCtrls) ctrl.dispose();
    for (var ctrl in _contentCtrls) ctrl.dispose();
    for (var node in _titleFocusNodes) node.dispose();
    for (var node in _contentFocusNodes) node.dispose();
    super.dispose();
  }

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
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _sections.length + 1,
              itemBuilder: (context, index) {
                if (index == _sections.length) {
                  return GestureDetector(
                    onTap: _addNewSection,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 40),
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
                  );
                }

                return _buildSectionCard(index);
              },
            ),
          ),

          // Bottom Action Bar (Voice, Link, etc)
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
}
