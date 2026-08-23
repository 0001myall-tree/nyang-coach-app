class TodayGoalTaskIntent {
  final String title;

  const TodayGoalTaskIntent._(this.title);

  static TodayGoalTaskIntent? parse(String input) {
    final original = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (original.isEmpty) return null;

    final context = _IntentContext.from(original);
    if (!context.isTodayTaskContext) return null;

    final title = _taskTitle(original);
    if (title == null || title.isEmpty) return null;
    return TodayGoalTaskIntent._(title);
  }

  static bool isTodayTaskGoalExpression(String input) => parse(input) != null;

  static String? _taskTitle(String original) {
    final sentences = original
        .split(RegExp(r'[.!?。！？]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final todaySentence = sentences.lastWhere(
      (part) => _IntentContext.from(part).hasTodayHorizon,
      orElse: () => original,
    );

    final carryAmount = _firstAmount(original);
    var title = todaySentence;
    title = title.replaceAll(RegExp(r'^(?:내가|나는|나|저는|저)\s+'), '');
    title = title.replaceAll(RegExp(r'오늘(?:은|도|까지)?'), ' ');
    title = title.replaceAll(RegExp(r'어제(?:처럼|만큼|정도)?'), ' ');
    title = title.replaceAll(RegExp(r'그걸|그것을|그거를|그거'), ' ');
    final goalIsMatch = RegExp(
      r'(.+?)(?:이|가)\s*목표(?:야|다|예요|입니다)?\s*$',
    ).firstMatch(title.trim());
    if (goalIsMatch != null) {
      title = goalIsMatch.group(1)!.trim();
    }
    title = title.replaceFirst(RegExp(r'^.*?목표(?:는|은)\s*'), ' ');
    title = title.replaceAll(
      RegExp(r'\s*(?:이|가)?\s*목표(?:야|다|예요|입니다)?\s*$'),
      ' ',
    );
    title = title.replaceAll(
      RegExp(
        r'\s*목표(?:로)?\s*(?:하(?:려고|려구|겠다|겠어|자|고\s*싶어)(?:\s*해)?|삼(?:으려고|겠다))\s*$',
      ),
      ' ',
    );
    title = title.replaceAll(RegExp(r'\s*(?:야|이야|예요|입니다)\s*$'), ' ');
    title = title.replaceAll(
      RegExp(
        r'\s*(?:할\s*거야|할거야|쓸\s*거야|쓸거야|읽을\s*거야|읽을거야|들을\s*거야|들을거야|할\s*게|할게|하려고|하려구|할래|할\s*래|해야지|해야겠다|해야겠어|할\s*것|할것|쓸\s*거|쓸거|읽을\s*거|읽을거|들을\s*거|들을거)\s*$',
      ),
      ' ',
    );
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (title.isEmpty || title == '도' || title == '그걸' || title == '해') {
      title = carryAmount ?? '';
    }
    if (!RegExp(r'\d').hasMatch(title) && carryAmount != null) {
      title = '$carryAmount $title'.trim();
    }
    if (title == carryAmount && RegExp(r'쓰|쓸|썼|집필|작성').hasMatch(original)) {
      title = '$carryAmount 쓰기';
    }

    title = _normalizeVerbTitle(title, carryAmount: carryAmount);
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? null : title;
  }

  static String? _firstAmount(String text) {
    final match = RegExp(
      r'(\d[\d,]*)\s*(자|글자|쪽|페이지|장|개|강|강의|분|시간|회|번)',
    ).firstMatch(text);
    if (match == null) return null;
    final unit = match.group(2) == '글자' ? '자' : match.group(2)!;
    return '${match.group(1)}$unit';
  }

  static String _normalizeVerbTitle(String title, {String? carryAmount}) {
    final compact = title.replaceAll(RegExp(r'\s+'), '');
    final amount = _firstAmount(title) ?? carryAmount;
    if (amount != null) {
      if (RegExp(r'쓰|쓸|집필|작성').hasMatch(compact)) {
        return _ensureAmountWithVerb(title, amount, '쓰기');
      }
      if (RegExp(r'책|읽|페이지|쪽').hasMatch(compact)) {
        return _ensureAmountWithVerb(title, amount, '읽기');
      }
      if (RegExp(r'강의|강|듣').hasMatch(compact)) {
        return _ensureAmountWithVerb(title, amount, '듣기');
      }
      if (RegExp(r'공부').hasMatch(compact)) {
        return _ensureAmountWithVerb(title, amount, '공부하기');
      }
      if (title == amount) {
        if (RegExp(r'(?:자|글자)$').hasMatch(amount)) return '$amount 쓰기';
        if (RegExp(r'(?:쪽|페이지)$').hasMatch(amount)) return '$amount 읽기';
        if (RegExp(r'(?:강|강의)$').hasMatch(amount)) return '$amount 듣기';
        return '$amount 하기';
      }
    }
    return title;
  }

  static String _ensureAmountWithVerb(
    String title,
    String amount,
    String verb,
  ) {
    var cleaned = title;
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:쓸|쓴|쓰는|쓰기|읽을|읽는|읽기|들을|듣는|듣기|공부)$'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!cleaned.replaceAll(RegExp(r'\s+'), '').contains(amount)) {
      cleaned = '$amount $cleaned'.trim();
    }
    return '$cleaned $verb'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _IntentContext {
  final String text;
  final String compact;

  const _IntentContext._(this.text, this.compact);

  factory _IntentContext.from(String text) {
    return _IntentContext._(text, text.replaceAll(RegExp(r'\s+'), ''));
  }

  bool get isTodayTaskContext {
    return hasTodayHorizon &&
        hasConcreteActionOrAmount &&
        !asksGoalFeatureSurface &&
        !hasLongTermHorizon;
  }

  bool get hasTodayHorizon {
    return RegExp(r'오늘(?:은|도|까지)?|금일').hasMatch(compact);
  }

  bool get hasLongTermHorizon {
    return RegExp(
      r'올해|내년|인생|장기|최종|언젠가|앞으로|이번\s*달|이번달|이번\s*주|이번주|월간|주간',
    ).hasMatch(text);
  }

  bool get asksGoalFeatureSurface {
    final asksAppSurface = RegExp(r'목표\s*(?:탭|텝|화면|창)').hasMatch(text);
    final asksGoalOperation = RegExp(
      r'목표.*(?:보여|열어|가줘|데려|수정|편집|삭제|지워|어디|확인)',
    ).hasMatch(compact);
    return asksAppSurface || asksGoalOperation;
  }

  bool get hasConcreteActionOrAmount {
    return hasAmount || hasActionVerb;
  }

  bool get hasAmount {
    return RegExp(
      r'\d[\d,]*(?:자|글자|쪽|페이지|장|개|강|강의|분|시간|회|번)',
    ).hasMatch(compact);
  }

  bool get hasActionVerb {
    return RegExp(
      r'쓰|읽|공부|운동|정리|청소|만들|작성|제출|풀|듣|외우|연습|작업|집필',
    ).hasMatch(compact);
  }
}
