import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import '../screens/coach_config.dart';
import '../services/notification_service.dart';
import '../services/tasks_sync_service.dart';

Future<bool> showCoreReminderSettingsSheet(BuildContext context) async {
  final userData = await UserDataService.load();
  if (!userData.isPlanActive) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friends 또는 Master 플랜에서 이용할 수 있어요.')),
      );
    }
    return false;
  }

  final prefs = await SharedPreferences.getInstance();
  var tempEnabled = true;
  var tempCoachId = prefs.getString('nyang_core_reminder_coach') ?? 'push';
  var tempAdvance = prefs.getInt('nyang_core_reminder_advance') ?? 10;

  if (!context.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          return Container(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              24 + MediaQuery.of(sheetContext).viewPadding.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_none,
                          color: Color(0xFF8B7CFF),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '코치의 일정 알람',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),
                    CupertinoSwitch(
                      value: tempEnabled,
                      activeColor: const Color(0xFF8B7CFF),
                      onChanged: (val) =>
                          setModalState(() => tempEnabled = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '원하는 일정을 알려드려요.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFA78BFA),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                Opacity(
                  opacity: tempEnabled ? 1 : 0.5,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '알람 시간 선택',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        Container(
                          width: 168,
                          height: 40,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [10, 30].map((minutes) {
                              final isActive = tempAdvance == minutes;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: tempEnabled
                                      ? () => setModalState(
                                          () => tempAdvance = minutes,
                                        )
                                      : null,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? const Color(0xFF8B7CFF)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      '$minutes분 전',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: isActive
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '알람 코치 선택',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Opacity(
                    opacity: tempEnabled ? 1 : 0.5,
                    child: ListView(
                      children: [
                        _CoreReminderCoachItem(
                          id: 'push',
                          name: '기본 푸쉬 알람',
                          subtitle: '코치 없이 조용하게 시스템 알람만 받아요',
                          isSelected: tempCoachId == 'push',
                          onTap: tempEnabled
                              ? () => setModalState(() => tempCoachId = 'push')
                              : null,
                        ),
                        const _CoreReminderSectionHeader('FRIENDS 코치'),
                        ...CoachConfigs.all.values
                            .where((coach) => coach.tier == 'friends')
                            .map(
                              (coach) => _CoreReminderCoachItem(
                                id: coach.id,
                                name: coach.name,
                                subtitle: '',
                                imagePath: coach.imagePath,
                                isSelected: tempCoachId == coach.id,
                                onTap: tempEnabled
                                    ? () => setModalState(
                                        () => tempCoachId = coach.id,
                                      )
                                    : null,
                              ),
                            ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFEDEAF8),
                          ),
                        ),
                        const _CoreReminderSectionHeader('MASTER 코치'),
                        ...CoachConfigs.all.values
                            .where((coach) => coach.tier == 'master')
                            .map(
                              (coach) => _CoreReminderCoachItem(
                                id: coach.id,
                                name: coach.name,
                                subtitle: '',
                                imagePath: coach.imagePath,
                                isSelected: tempCoachId == coach.id,
                                onTap: tempEnabled
                                    ? () => setModalState(
                                        () => tempCoachId = coach.id,
                                      )
                                    : null,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      await prefs.setBool(
                        'nyang_core_reminder_enabled',
                        tempEnabled,
                      );
                      await prefs.setString(
                        'nyang_core_reminder_coach',
                        tempCoachId,
                      );
                      await prefs.setInt(
                        'nyang_core_reminder_advance',
                        tempAdvance,
                      );
                      TasksSyncService.scheduleSyncToCloud();
                      NotificationService().syncCoreReminders();
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, tempEnabled);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      '저장하기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  return saved == true;
}

class _CoreReminderSectionHeader extends StatelessWidget {
  const _CoreReminderSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

class _CoreReminderCoachItem extends StatelessWidget {
  const _CoreReminderCoachItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isSelected,
    this.onTap,
    this.imagePath,
  });

  final String id;
  final String name;
  final String subtitle;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3F0FF) : Colors.white,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF8B7CFF)
                : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            if (id == 'push')
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.notifications_active,
                  color: Color(0xFF9CA3AF),
                  size: 24,
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  image: DecorationImage(
                    image: AssetImage(imagePath!),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? const Color(0xFF8B7CFF)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF8B7CFF)
                      : const Color(0xFFE5E7EB),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF8B7CFF),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
