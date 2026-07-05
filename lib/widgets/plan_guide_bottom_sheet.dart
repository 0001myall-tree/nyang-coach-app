import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_design_tokens.dart';
import 'app_bottom_sheet.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'app_chip.dart';

Future<void> showPlanGuideBottomSheet(
  BuildContext context, {
  VoidCallback? onLearnMore,
  String checkoutLabel = '플랜 시작하기',
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return _PlanGuideBottomSheet(
        onLearnMore: onLearnMore,
        checkoutLabel: checkoutLabel,
      );
    },
  );
}

class _PlanGuideBottomSheet extends StatefulWidget {
  const _PlanGuideBottomSheet({this.onLearnMore, required this.checkoutLabel});

  final VoidCallback? onLearnMore;
  final String checkoutLabel;

  @override
  State<_PlanGuideBottomSheet> createState() => _PlanGuideBottomSheetState();
}

class _PlanGuideBottomSheetState extends State<_PlanGuideBottomSheet> {
  bool _isSixMonth = false;
  String? _selectedPlanId;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetScaffold(
      backgroundColor: const Color(0xFFFFFBFF),
      showHandle: false,
      contentPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlanGuideHeader(
              isSixMonth: _isSixMonth,
              onChanged: (value) {
                setState(() => _isSixMonth = value);
              },
              onClose: () => Navigator.pop(context),
            ),
            Transform.translate(
              offset: const Offset(0, -104),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesignTokens.sheetHorizontalPadding,
                  18,
                  AppDesignTokens.sheetHorizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlanGroup(
                      isMaster: false,
                      title: '프렌즈 플랜',
                      subtitle: '실행코치와 동기부여 대화 및 플래너',
                      price: _isSixMonth ? '29,400원' : '5,900원 / 월',
                      originalPrice: _isSixMonth ? '35,400원' : null,
                      badge: _isSixMonth ? '6개월 총액' : '매월 자동 결제',
                      subPrice: _isSixMonth ? '월 4,900원' : null,
                      isSelected: _selectedPlanId == 'friends',
                      onTap: () {
                        setState(() => _selectedPlanId = 'friends');
                      },
                      features: const [
                        (Icons.check_circle_rounded, '실행코치와 동기부여 대화 및 플래너'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PlanGroup(
                      isMaster: true,
                      title: '마스터 플랜',
                      subtitle: '비서 코치와 목표 달성을 더 촘촘하게 관리',
                      price: _isSixMonth ? '47,400원' : '8,900원 / 월',
                      originalPrice: _isSixMonth ? '53,400원' : null,
                      badge: _isSixMonth ? '6개월 총액' : '매월 자동 결제',
                      subPrice: _isSixMonth ? '월 7,900원' : null,
                      isSelected: _selectedPlanId == 'master',
                      onTap: () {
                        setState(() => _selectedPlanId = 'master');
                      },
                      features: const [
                        (Icons.check_circle_rounded, '비서 코치 이용'),
                        (Icons.check_circle_rounded, '실행코치와 동기부여 대화 및 플래너'),
                        (Icons.check_circle_rounded, '지금 뭐하지?'),
                        (Icons.check_circle_rounded, '주간 회고 & 우선순위 추천'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _IndividualCoachGuide(),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        '모든 구독 플랜은 냥냥 코치를 포함합니다.',
                        style: GoogleFonts.notoSansKr(
                          fontSize: AppDesignTokens.textCaption,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.brand,
                        ),
                      ),
                    ),
                    if (widget.onLearnMore != null) ...[
                      const SizedBox(height: 14),
                      _NyangCoachLearnMoreButton(onTap: widget.onLearnMore!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      footer: _PlanCheckoutBar(
        selectedPlanId: _selectedPlanId,
        checkoutLabel: widget.checkoutLabel,
      ),
    );
  }
}

class _PlanGuideHeader extends StatelessWidget {
  const _PlanGuideHeader({
    required this.isSixMonth,
    required this.onChanged,
    required this.onClose,
  });

  final bool isSixMonth;
  final ValueChanged<bool> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 고양이 배경 이미지 제거됨
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
          Positioned(
            top: 44,
            right: 22,
            child: TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8E8A9E),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '닫기',
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textCaption + 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 104,
            child: _PlanPeriodTabs(
              isSixMonth: isSixMonth,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPeriodTabs extends StatelessWidget {
  const _PlanPeriodTabs({required this.isSixMonth, required this.onChanged});

  final bool isSixMonth;
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
              subtitle: '매월 자동 결제',
              isSelected: !isSixMonth,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _PlanPeriodTab(
              title: '6개월 구독',
              subtitle: '한 번 결제로 더 큰 혜택',
              isSelected: isSixMonth,
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
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
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
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                fontSize: AppDesignTokens.textBody,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : AppDesignTokens.brandPressed,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppDesignTokens.brandMuted,
              ),
            ),
          ],
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
    required this.badge,
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
  final String badge;
  final List<(IconData, String)> features;
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
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppDesignTokens.premium,
                  size: 28,
                )
              else
                const Icon(
                  Icons.eco_rounded,
                  color: AppDesignTokens.brand,
                  size: 28,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandStrong,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppDesignTokens.brand,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: AppDesignTokens.textCaption,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.brandTextMuted,
            ),
          ),
          const SizedBox(height: 14),
          _PlanPriceBox(
            badge: badge,
            price: price,
            originalPrice: originalPrice,
            subPrice: subPrice,
            features: features,
          ),
        ],
      ),
    );
  }
}

class _PlanPriceBox extends StatelessWidget {
  const _PlanPriceBox({
    required this.badge,
    required this.price,
    required this.features,
    this.originalPrice,
    this.subPrice,
  });

  final String badge;
  final String price;
  final List<(IconData, String)> features;
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
          AppChip(
            label: badge,
            selected: true,
            borderColor: Colors.transparent,
            selectedBackgroundColor: const Color(0xFFF3F0FF),
            selectedForegroundColor: const Color(0xFF6D28D9),
          ),
          const SizedBox(height: 12),
          if (originalPrice != null) ...[
            Text(
              '정가 $originalPrice',
              style: GoogleFonts.notoSansKr(
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
                  child: Text(
                    price,
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.brandStrong,
                    ),
                  ),
                ),
              ),
              if (subPrice != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    subPrice!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                      fontSize: AppDesignTokens.textCaption,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.brandTextMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppDesignTokens.brandBorder, height: 1),
          const SizedBox(height: 12),
          ...features.map((feature) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(feature.$1, size: 18, color: const Color(0xFFD8D2FF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature.$2,
                      style: GoogleFonts.notoSansKr(
                        fontSize: AppDesignTokens.textCaption + 1,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2F2A44),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
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
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '남친, 할매, 여친, 갓생 형 코치를 1년 이용권으로 추가할 수 있어요.',
                  style: GoogleFonts.notoSansKr(
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
              '3,900원',
              style: GoogleFonts.notoSansKr(
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

class _NyangCoachLearnMoreButton extends StatelessWidget {
  const _NyangCoachLearnMoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: '냥냥코치 더 알아보기',
      variant: AppButtonVariant.secondary,
      onPressed: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

class _PlanCheckoutBar extends StatelessWidget {
  const _PlanCheckoutBar({
    required this.selectedPlanId,
    required this.checkoutLabel,
  });

  final String? selectedPlanId;
  final String checkoutLabel;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: selectedPlanId == null ? '플랜을 선택해주세요' : checkoutLabel,
      icon: const Icon(Icons.pets),
      backgroundColor: AppDesignTokens.brandAccent,
      disabledBackgroundColor: AppDesignTokens.brandDisabled,
      onPressed: selectedPlanId == null
          ? null
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '결제 화면은 곧 연결할게요.',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusMedium,
                    ),
                  ),
                ),
              );
            },
    );
  }
}
