import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_font.dart';

import '../theme/app_design_tokens.dart';
import '../services/plan_catalog.dart';
import '../services/purchase_service.dart';
import 'app_bottom_sheet.dart';
import 'app_button.dart';
import 'app_card.dart';

/// 구독 안내에서 고른 플랜. "더 알아보기"로 나갔다 돌아올 때 들고 다닌다.
typedef PlanSelection = ({String planId, bool isLongTerm});

/// [onLearnMore]는 그때 고른 플랜을 받는다(안 골랐으면 null).
///
/// [initialSelection]을 주면 그 플랜이 골라진 채로 열리고, [checkoutOnOpen]이면
/// 열리자마자 결제를 시작한다 — 소개를 읽고 "함께 시작하기"를 누른 사람에게
/// 같은 플랜을 또 고르게 하지 않는다.
Future<void> showPlanGuideBottomSheet(
  BuildContext context, {
  void Function(PlanSelection? selection)? onLearnMore,
  Future<void> Function()? onPurchaseCompleted,
  String checkoutLabel = '플랜 시작하기',
  PlanSelection? initialSelection,
  bool checkoutOnOpen = false,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return _PlanGuideBottomSheet(
        onLearnMore: onLearnMore,
        onPurchaseCompleted: onPurchaseCompleted,
        checkoutLabel: checkoutLabel,
        initialSelection: initialSelection,
        checkoutOnOpen: checkoutOnOpen,
      );
    },
  );
}

class _PlanGuideBottomSheet extends StatefulWidget {
  const _PlanGuideBottomSheet({
    this.onLearnMore,
    this.onPurchaseCompleted,
    required this.checkoutLabel,
    this.initialSelection,
    this.checkoutOnOpen = false,
  });

  final void Function(PlanSelection? selection)? onLearnMore;
  final PlanSelection? initialSelection;
  final bool checkoutOnOpen;
  final Future<void> Function()? onPurchaseCompleted;
  final String checkoutLabel;

  @override
  State<_PlanGuideBottomSheet> createState() => _PlanGuideBottomSheetState();
}

class _PlanGuideBottomSheetState extends State<_PlanGuideBottomSheet> {
  bool _isLongTerm = false;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  String? _selectedPlanId;

  PlanCatalog get _catalog => PlanCatalog.instance;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSelection;
    if (initial != null) {
      _selectedPlanId = initial.planId;
      _isLongTerm = initial.isLongTerm;
      if (widget.checkoutOnOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleCheckout();
        });
      }
    }
    // 팔 것이 바뀌었을 수 있다. 열릴 때 한 번 확인하고, 늦게 오면 그때 다시 그린다.
    _catalog.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 화면에 쓸 상품. 서버 목록에 없으면 그 자리는 비워둔다.
  PurchasePlan? _planFor(String planType) =>
      _catalog.planFor(planType, isLongTerm: _isLongTerm);

  Future<void> _handleCheckout() async {
    final selectedPlanId = _selectedPlanId;
    if (selectedPlanId == null || _isPurchasing || _isRestoring) return;

    final plan = PurchaseService.instance.planForSelection(
      selectedPlanId,
      _isLongTerm,
    );
    if (plan == null) {
      _showSnackBar('선택한 플랜을 찾지 못했어요.');
      return;
    }

    setState(() => _isPurchasing = true);
    final result = await PurchaseService.instance.purchase(plan);
    if (!mounted) return;

    setState(() => _isPurchasing = false);
    _showSnackBar(result.message);
    if (!result.success) return;

    await widget.onPurchaseCompleted?.call();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleRestore() async {
    if (_isPurchasing || _isRestoring) return;

    setState(() => _isRestoring = true);
    await PurchaseService.instance.restorePurchases();
    await widget.onPurchaseCompleted?.call();
    if (!mounted) return;

    setState(() => _isRestoring = false);
    _showSnackBar('결제 기록을 확인하고 있어요. 잠시 후 반영돼요.');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: appFont(fontWeight: FontWeight.w700)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetScaffold(
      backgroundColor: AppDesignTokens.brandSurface,
      showHandle: false,
      contentPadding: EdgeInsets.zero,
      // 닫기·제목·기간 탭은 고정하고 플랜 목록만 스크롤한다. 같이 스크롤되면
      // 플랜을 보느라 내려간 사이 지금 월간을 보는지 6개월을 보는지가 사라지고,
      // 닫으려면 다시 끝까지 올려야 했다.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlanGuideHeader(
            onLearnMore: widget.onLearnMore == null
                ? null
                : () => widget.onLearnMore!(
                    _selectedPlanId == null
                        ? null
                        : (planId: _selectedPlanId!, isLongTerm: _isLongTerm),
                  ),
            isLongTerm: _isLongTerm,
            longTermLabel: _catalog.longTermLabel,
            onChanged: (value) {
              setState(() => _isLongTerm = value);
            },
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesignTokens.sheetHorizontalPadding,
                  4,
                  AppDesignTokens.sheetHorizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlanGroup(
                      isMaster: false,
                      title: '프렌즈 플랜',
                      subtitle: '가볍게 루틴 잡기',
                      price: _planFor('friends')?.price ?? '',
                      originalPrice: _planFor('friends')?.originalPrice,
                      subPrice: _planFor('friends')?.subPrice,
                      isSelected: _selectedPlanId == 'friends',
                      onTap: () {
                        setState(() => _selectedPlanId = 'friends');
                      },
                      features: const [
                        ('assets/icons/circle-check.svg', '냥냥코치 이용 가능'),
                        (
                          'assets/icons/circle-check.svg',
                          '매일 코치와 대화하며 하루 계획 관리',
                        ),
                        (
                          'assets/icons/wand-magic-sparkles.svg',
                          '말 한마디로 일정 추가',
                        ),
                        ('assets/icons/shield-cat.svg', '딴짓 코칭'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PlanGroup(
                      isMaster: true,
                      title: '마스터 플랜',
                      subtitle: '비서 코치와 목표 달성을 더 촘촘하게 관리',
                      price: _planFor('master')?.price ?? '',
                      originalPrice: _planFor('master')?.originalPrice,
                      subPrice: _planFor('master')?.subPrice,
                      isSelected: _selectedPlanId == 'master',
                      onTap: () {
                        setState(() => _selectedPlanId = 'master');
                      },
                      features: const [
                        ('assets/icons/circle-check.svg', '비서 코치, 냥냥코치 이용 가능'),
                        (
                          'assets/icons/circle-check.svg',
                          '매일 코치와 대화하며 하루 계획 관리',
                        ),
                        (
                          'assets/icons/wand-magic-sparkles.svg',
                          '말 한마디로 일정 추가',
                        ),
                        ('assets/icons/shield-cat.svg', '딴짓 코칭'),
                        ('assets/icons/thumbtack.svg', '미루는 항목 마무리될 때까지 적극 코칭'),
                        (
                          'assets/icons/magnifying-glass-chart.svg',
                          '더 세밀한 실행 패턴 분석',
                        ),
                      ],
                    ),
                    // 코치 한 명만 사는 길이 닫혀 있으면 값도 알리지 않는다.
                    if (PurchaseService.singleCoachPurchaseEnabled) ...[
                      const SizedBox(height: 14),
                      const _IndividualCoachGuide(),
                    ],
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        '모든 구독 플랜은 냥냥 코치를 포함합니다.',
                        style: appFont(
                          fontSize: AppDesignTokens.textCaption,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // 틀의 기본 아래 여백은 내비게이션 바 높이를 한 번 더 비워둬서, 버튼
      // 아래가 크게 떠 있었다. 이 창은 버튼이 셋이라 아래로 붙인다.
      footerPadding: const EdgeInsets.fromLTRB(
        AppDesignTokens.sheetFooterHorizontalPadding,
        AppDesignTokens.sheetFooterTopPadding,
        AppDesignTokens.sheetFooterHorizontalPadding,
        8,
      ),
      footer: _PlanCheckoutBar(
        selectedPlanId: _selectedPlanId,
        checkoutLabel: widget.checkoutLabel,
        isProcessing: _isPurchasing,
        isRestoring: _isRestoring,
        onCheckout: _handleCheckout,
        onRestore: _handleRestore,
      ),
    );
  }
}

class _PlanGuideHeader extends StatelessWidget {
  const _PlanGuideHeader({
    this.onLearnMore,
    required this.isLongTerm,
    required this.longTermLabel,
    required this.onChanged,
    required this.onClose,
  });

  /// "냥냥코치란?". 큰 버튼으로 결제 버튼 위에 두었더니 결제 앞을 가로막고
  /// 플랜 목록 자리까지 먹어서, 궁금한 사람만 누르는 작은 버튼으로 내렸다.
  final VoidCallback? onLearnMore;
  final bool isLongTerm;
  final String longTermLabel;
  final ValueChanged<bool> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 226,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 22,
            left: 0,
            right: 0,
            child: Center(
              child: AppBottomSheetHandle(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          if (onLearnMore != null)
            Positioned(
              top: 38,
              left: AppDesignTokens.sheetHorizontalPadding,
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(
                  side: BorderSide(color: AppDesignTokens.brandBorder),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    Navigator.pop(context);
                    onLearnMore!();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      '냥냥코치란?',
                      style: appFont(
                        fontSize: AppDesignTokens.textCaption + 1,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.brandTextMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 44,
            right: 22,
            child: TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.brandTextMuted,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '닫기',
                style: appFont(
                  fontSize: AppDesignTokens.textCaption + 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            top: 92,
            left: AppDesignTokens.sheetHorizontalPadding,
            right: AppDesignTokens.sheetHorizontalPadding,
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: appFont(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textPrimary,
                  height: 1.35,
                ),
                children: const [
                  TextSpan(
                    text: '구독 플랜',
                    style: TextStyle(
                      color: AppDesignTokens.brand,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: '을 선택하세요'),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 160,
            child: _PlanPeriodTabs(
              isLongTerm: isLongTerm,
              longTermLabel: longTermLabel,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPeriodTabs extends StatelessWidget {
  const _PlanPeriodTabs({
    required this.isLongTerm,
    required this.longTermLabel,
    required this.onChanged,
  });

  final bool isLongTerm;
  final String longTermLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppDesignTokens.brandChip,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppDesignTokens.brandBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PlanPeriodTab(
              title: '월간 구독',
              isSelected: !isLongTerm,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _PlanPeriodTab(
              title: '$longTermLabel 구독',
              isSelected: isLongTerm,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPeriodTab extends StatelessWidget {
  const _PlanPeriodTab({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppDesignTokens.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: AppDesignTokens.textBody,
            fontWeight: FontWeight.w900,
            color: isSelected ? Colors.white : AppDesignTokens.brandPressed,
          ),
        ),
      ),
    );
  }
}

class _PlanGroup extends StatelessWidget {
  const _PlanGroup({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.features,
    required this.isSelected,
    required this.onTap,
    required this.isMaster,
    this.originalPrice,
    this.subPrice,
  });

  final String title;
  final String subtitle;
  final String price;
  final List<(String, String)> features;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isMaster;
  final String? originalPrice;
  final String? subPrice;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      selected: isSelected,
      backgroundColor: isSelected
          ? AppDesignTokens.brandSoftAlt
          : Colors.white.withValues(alpha: 0.9),
      borderColor: AppDesignTokens.brandCardBorder,
      shadows: [
        BoxShadow(
          color: AppDesignTokens.brand.withValues(
            alpha: isSelected ? 0.18 : 0.08,
          ),
          blurRadius: isSelected ? 18 : 16,
          offset: const Offset(0, 8),
        ),
      ],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isMaster)
                const _PlanCoachAvatars(
                  imagePaths: [
                    'assets/images/cat_nobg.png',
                    'assets/images/coach_nyang_halbae_nobg.png',
                  ],
                )
              else
                const _PlanCoachAvatar(
                  imagePath: 'assets/images/cat_nobg.png',
                  size: 32,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: appFont(
              fontSize: AppDesignTokens.textCaption,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.brandTextMuted,
            ),
          ),
          const SizedBox(height: 14),
          _PlanPriceBox(
            price: price,
            originalPrice: originalPrice,
            subPrice: subPrice,
            features: features,
            expanded: isSelected,
          ),
        ],
      ),
    );
  }
}

class _PlanCoachAvatars extends StatelessWidget {
  const _PlanCoachAvatars({required this.imagePaths});

  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < imagePaths.length; index++)
            Positioned(
              left: index * 20,
              child: _PlanCoachAvatar(
                imagePath: imagePaths[index],
                size: index == imagePaths.length - 1 ? 36 : 32,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCoachAvatar extends StatelessWidget {
  const _PlanCoachAvatar({required this.imagePath, required this.size});

  final String imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppDesignTokens.brandBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }
}

class _PlanPriceBox extends StatelessWidget {
  const _PlanPriceBox({
    required this.price,
    required this.features,
    required this.expanded,
    this.originalPrice,
    this.subPrice,
  });

  final String price;
  final List<(String, String)> features;

  /// 혜택 목록을 펼칠지. 고른 카드만 펼친다 — 둘 다 펼쳐두면 프렌즈 카드가
  /// 화면을 다 차지해서 마스터 플랜이 있는 줄도 모른 채 지나간다.
  final bool expanded;
  final String? originalPrice;
  final String? subPrice;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: AppDesignTokens.cardInnerRadius,
      backgroundColor: AppDesignTokens.brandSurface,
      borderColor: AppDesignTokens.brandBorder,
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (originalPrice != null) ...[
            Text(
              '정가 $originalPrice',
              style: appFont(
                fontSize: AppDesignTokens.textCaption + 1,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.brandPriceMuted,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppDesignTokens.brandPriceMuted,
                decorationThickness: 2,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _PlanPriceText(price),
                ),
              ),
              if (subPrice != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    subPrice!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: AppDesignTokens.textCaption,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.brandTextMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Divider(
                        color: AppDesignTokens.brandBorder,
                        height: 1,
                      ),
                      const SizedBox(height: 12),
                      ..._featureRows(),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '눌러서 혜택 보기 ▾',
                      style: appFont(
                        fontSize: AppDesignTokens.textCaption,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.brandPriceMuted,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _featureRows() => [
    ...features.map((feature) {
      // 마스터에만 있는 것을 진하게. 문구를 바꾸면 여기도 같이 바꿔야 한다.
      final isSignatureFeature =
          feature.$2 == '미루는 항목 마무리될 때까지 적극 코칭' ||
          feature.$2 == '더 세밀한 실행 패턴 분석';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SvgPicture.asset(
              feature.$1,
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                AppDesignTokens.brandDisabled,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                feature.$2,
                style: appFont(
                  fontSize: AppDesignTokens.textCaption + 1,
                  fontWeight: isSignatureFeature
                      ? FontWeight.w900
                      : FontWeight.w700,
                  color: isSignatureFeature
                      ? AppDesignTokens.brandStrong
                      : AppDesignTokens.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }),
  ];
}

class _PlanPriceText extends StatelessWidget {
  const _PlanPriceText(this.price);

  final String price;

  @override
  Widget build(BuildContext context) {
    final unitStart = price.indexOf('원');
    if (unitStart < 0) {
      return Text(
        price,
        maxLines: 1,
        style: appFont(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: AppDesignTokens.brandStrong,
        ),
      );
    }

    return RichText(
      maxLines: 1,
      text: TextSpan(
        style: appFont(
          color: AppDesignTokens.brandStrong,
          fontWeight: FontWeight.w900,
        ),
        children: [
          TextSpan(
            text: price.substring(0, unitStart),
            // 제목(24)보다 한 단계 아래. 같거나 크면 제목과 겨룬다.
            style: const TextStyle(fontSize: 22),
          ),
          TextSpan(
            text: price.substring(unitStart),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _IndividualCoachGuide extends StatelessWidget {
  const _IndividualCoachGuide();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: Colors.white.withValues(alpha: 0.9),
      borderColor: AppDesignTokens.brandCardBorder,
      shadows: const [],
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppDesignTokens.brandChip,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: AppDesignTokens.brand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '개별 코치 추가 이용',
                  style: appFont(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '햇살, 할매, 갓생 형 코치를 1년 이용권으로 추가할 수 있어요.',
                  style: appFont(
                    fontSize: AppDesignTokens.textCaption,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.brandTextMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '2,900원',
              style: appFont(
                fontSize: AppDesignTokens.textAction,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.brandStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCheckoutBar extends StatelessWidget {
  const _PlanCheckoutBar({
    required this.selectedPlanId,
    required this.checkoutLabel,
    required this.isProcessing,
    required this.isRestoring,
    required this.onCheckout,
    required this.onRestore,
  });

  final String? selectedPlanId;
  final String checkoutLabel;
  final bool isProcessing;
  final bool isRestoring;
  final VoidCallback onCheckout;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final disabled = selectedPlanId == null || isProcessing || isRestoring;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: selectedPlanId == null
              ? '플랜을 선택해주세요'
              : isProcessing
              ? '결제 확인 중...'
              : checkoutLabel,
          icon: const Icon(Icons.pets),
          backgroundColor: AppDesignTokens.brandAccent,
          disabledBackgroundColor: AppDesignTokens.brandDisabled,
          onPressed: disabled ? null : onCheckout,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: isProcessing || isRestoring ? null : onRestore,
          style: TextButton.styleFrom(
            foregroundColor: AppDesignTokens.brandPressed,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            // 앱을 다시 깔았거나 폰을 바꿨을 때 이미 낸 구독을 다시 가져오는
            // 버튼. 애플 심사에 꼭 있어야 한다.
            isRestoring ? '불러오는 중...' : '이전에 결제한 구독 불러오기',
            style: appFont(
              fontSize: AppDesignTokens.textCaption + 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        // 버튼 이름만으로는 언제 누르는 것인지 감이 안 온다.
        Text(
          '앱을 다시 설치했거나 폰을 바꿨다면 눌러주세요',
          style: appFont(
            fontSize: AppDesignTokens.textCaption,
            fontWeight: FontWeight.w500,
            color: AppDesignTokens.brandPriceMuted,
          ),
        ),
      ],
    );
  }
}
