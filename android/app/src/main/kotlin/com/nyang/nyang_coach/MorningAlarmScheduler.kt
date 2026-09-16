package com.coscene.nyangcoach

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

object MorningAlarmScheduler {
    private const val REQUEST_CODE = 7301
    private const val SHOW_REQUEST_CODE = 7302
    const val ACTION_FIRE = "com.coscene.nyangcoach.MORNING_ALARM_FIRE"
    const val ACTION_SHOW = "com.coscene.nyangcoach.MORNING_ALARM_SHOW"
    const val ACTION_FOLLOW_UP = "com.coscene.nyangcoach.MORNING_ALARM_FOLLOW_UP"
    const val EXTRA_PAYLOAD = "payload"

    /**
     * 첫 알람 뒤에 한 번씩 더 부르는 시각. 분 단위다.
     *
     * 폰이 잠겨 있으면 첫 알람이 화면을 띄우고 목소리가 끌 때까지 반복되므로
     * 이것들은 할 일이 없다. 문제는 폰을 쓰는 중일 때다. 그때 안드로이드는
     * 전체화면을 안 띄우고 배너로 내리는데, 배너를 안 누르면 소리 한 번으로
     * 끝나버린다. 아이폰은 그 경우에도 1분 간격으로 세 번 울린다.
     */
    private val FOLLOW_UP_MINUTES = intArrayOf(1, 2)
    private val FOLLOW_UP_REQUEST_CODES = intArrayOf(7311, 7312)

    fun schedule(context: Context, triggerMillis: Long, payload: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("flutter.native_morning_trigger_millis", triggerMillis)
            .putString("flutter.native_morning_scheduled_payload", payload)
            .commit()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fireIntent = Intent(context, MorningAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_PAYLOAD, payload)
        }
        val firePendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            fireIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val showIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SHOW
            putExtra(EXTRA_PAYLOAD, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            SHOW_REQUEST_CODE,
            showIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(triggerMillis, showPendingIntent),
            firePendingIntent,
        )
    }

    /**
     * 첫 알람이 울린 그 자리에서 뒤따르는 것들을 건다.
     *
     * 예약할 때 미리 걸지 않는 이유가 있다. 첫 알람은 울리자마자 내일 것을
     * 다시 거는데, 그 길이 뒤따르는 것들까지 내일로 옮겨버린다. 아직 울리지도
     * 않은 것을 데려가는 셈이다. 그래서 울린 뒤 지금 시각을 기준으로 건다.
     */
    fun scheduleFollowUps(context: Context, payload: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (i in FOLLOW_UP_MINUTES.indices) {
            val intent = Intent(context, MorningAlarmReceiver::class.java).apply {
                action = ACTION_FOLLOW_UP
                putExtra(EXTRA_PAYLOAD, payload)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                FOLLOW_UP_REQUEST_CODES[i],
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                now + FOLLOW_UP_MINUTES[i] * 60_000L,
                pendingIntent,
            )
        }
    }

    private fun cancelFollowUps(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (requestCode in FOLLOW_UP_REQUEST_CODES) {
            val intent = Intent(context, MorningAlarmReceiver::class.java).apply {
                action = ACTION_FOLLOW_UP
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }
    }

    /**
     * "1,3,5" 같은 저장값을 요일 집합으로. Calendar.DAY_OF_WEEK 기준(일=1..토=7)이
     * 아니라 Dart와 맞춘 월=1..일=7 기준으로 저장돼 있어서 여기서도 그대로 쓴다.
     * 비어 있거나 못 읽으면 매일로 본다 — 요일 설정이 생기기 전부터 켜둔 사람의
     * 모닝콜이 갑자기 조용해지면 안 된다.
     */
    private fun parseDays(raw: String?): Set<Int> {
        if (raw.isNullOrBlank()) return (1..7).toSet()
        val days = raw.split(",").mapNotNull { it.trim().toIntOrNull() }
            .filter { it in 1..7 }
            .toSet()
        return days.ifEmpty { (1..7).toSet() }
    }

    /** [Calendar]는 일=1..토=7이다. 월=1..일=7로 맞춘다. */
    private fun Calendar.isoWeekday(): Int {
        val calDay = get(Calendar.DAY_OF_WEEK) // SUNDAY=1..SATURDAY=7
        return if (calDay == Calendar.SUNDAY) 7 else calDay - 1
    }

    fun rescheduleFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.nyang_morning_call_enabled", false)
        if (!enabled) {
            cancel(context)
            return
        }
        val payload = prefs.getString("flutter.native_morning_scheduled_payload", null) ?: return
        val time = prefs.getString("flutter.nyang_morning_call_time", null) ?: return
        val parts = time.split(":")
        if (parts.isEmpty()) return
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: return
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val days = parseDays(prefs.getString("flutter.nyang_morning_call_days", null))

        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DATE, 1)
            }
            // 요일이 안 맞으면 맞는 날이 나올 때까지 하루씩 민다.
            var guard = 0
            while (!days.contains(isoWeekday()) && guard < 7) {
                add(Calendar.DATE, 1)
                guard++
            }
        }
        schedule(context, next.timeInMillis, payload)
    }

    fun cancel(context: Context) {
        cancelFollowUps(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fireIntent = Intent(context, MorningAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
        }
        val firePendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            fireIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (firePendingIntent != null) {
            alarmManager.cancel(firePendingIntent)
            firePendingIntent.cancel()
        }

        val showIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SHOW
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            SHOW_REQUEST_CODE,
            showIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        showPendingIntent?.cancel()

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .remove("flutter.native_morning_trigger_millis")
            .remove("flutter.native_morning_scheduled_payload")
            .commit()
    }
}
