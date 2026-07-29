import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_id_service.dart';

class CoachIdMigrationService {
  static const String _doneKey = 'nyang_nyang_halbae_id_migrated_v1';

  static Future<void> migrateLegacyNyangHalbaeIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey) == true) return;

    try {
      await _copyKnownCoachKeys(prefs);
      await _copyGreetingVisitCountKeys(prefs);
      await _normalizeStoredCoachChoices(prefs);
      await _normalizeUserData(prefs);
      await prefs.setBool(_doneKey, true);
    } catch (e, stackTrace) {
      debugPrint('Nyang Halbae coach id migration failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> _copyKnownCoachKeys(SharedPreferences prefs) async {
    const oldId = CoachIdService.legacyNyangHalbaeId;
    const newId = CoachIdService.nyangHalbaeId;
    const suffixKeys = [
      'nyang_chat_history_',
      'nyang_chat_archive_',
      'last_visit_',
      'nyang_master_local_greeting_date_',
      'nyang_master_local_greeting_recent_lines_',
      'nyang_coach_weekly_feedback_',
      'nyang_coach_name_',
      'widget_',
    ];

    for (final prefix in suffixKeys) {
      final oldKey = '$prefix$oldId';
      final newKey = '$prefix$newId';
      if (!prefs.containsKey(oldKey) || prefs.containsKey(newKey)) continue;
      final value = prefs.get(oldKey);
      if (value is String) {
        await prefs.setString(newKey, value);
      } else if (value is bool) {
        await prefs.setBool(newKey, value);
      } else if (value is int) {
        await prefs.setInt(newKey, value);
      } else if (value is double) {
        await prefs.setDouble(newKey, value);
      } else if (value is List<String>) {
        await prefs.setStringList(newKey, value);
      }
    }
  }

  static Future<void> _copyGreetingVisitCountKeys(
    SharedPreferences prefs,
  ) async {
    const oldPrefix =
        'nyang_master_local_greeting_visit_count_${CoachIdService.legacyNyangHalbaeId}_';
    const newPrefix =
        'nyang_master_local_greeting_visit_count_${CoachIdService.nyangHalbaeId}_';

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(oldPrefix)) continue;
      final newKey = key.replaceFirst(oldPrefix, newPrefix);
      if (prefs.containsKey(newKey)) continue;
      final value = prefs.getInt(key);
      if (value != null) await prefs.setInt(newKey, value);
    }
  }

  static Future<void> _normalizeStoredCoachChoices(
    SharedPreferences prefs,
  ) async {
    const choiceKeys = [
      'nyang_selected_coach',
      'nyang_morning_call_coach',
      'nyang_core_reminder_coach',
      'nyang_core_reminder_resolved_coach',
    ];

    for (final key in choiceKeys) {
      final value = prefs.getString(key);
      if (value == CoachIdService.legacyNyangHalbaeId) {
        await prefs.setString(key, CoachIdService.nyangHalbaeId);
      }
    }
  }

  static Future<void> _normalizeUserData(SharedPreferences prefs) async {
    const key = 'nyang_user_data';
    final raw = prefs.getString(key);
    if (raw == null) return;

    final decodedRaw = jsonDecode(raw);
    if (decodedRaw is! Map) return;
    final decoded = decodedRaw.cast<String, dynamic>();
    var changed = false;

    if (decoded['selected_coach_id'] == CoachIdService.legacyNyangHalbaeId) {
      decoded['selected_coach_id'] = CoachIdService.nyangHalbaeId;
      changed = true;
    }

    final owned = decoded['owned_coaches'];
    if (owned is List && owned.contains(CoachIdService.legacyNyangHalbaeId)) {
      final normalized = owned
          .map((id) => CoachIdService.normalize(id?.toString()))
          .toSet()
          .toList();
      decoded['owned_coaches'] = normalized;
      changed = true;
    }

    final expires = decoded['owned_coach_expires_at'];
    if (expires is Map &&
        expires.containsKey(CoachIdService.legacyNyangHalbaeId)) {
      expires[CoachIdService.nyangHalbaeId] ??=
          expires[CoachIdService.legacyNyangHalbaeId];
      expires.remove(CoachIdService.legacyNyangHalbaeId);
      decoded['owned_coach_expires_at'] = expires;
      changed = true;
    }

    if (changed) {
      await prefs.setString(key, jsonEncode(decoded));
    }
  }
}
