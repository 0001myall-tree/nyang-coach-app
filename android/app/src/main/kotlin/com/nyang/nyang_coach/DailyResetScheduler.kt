package com.coscene.nyangcoach

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * 자정 5분 뒤에 하루 목록 정리를 돌리는 알람.
 *
 * 적극 코칭을 켜둔 사람에게만 건다. 정리 자체는 Dart가 한다 — 규칙을 여기에
 * 한 벌 더 두면 한쪽만 고쳐진다. 여기서는 그 시각에 깨워서 넘기기만 한다.
 *
 * 걸려 있는지는 접두어 없는 키에 따로 적는다. 폰을 껐다 켜면 알람이 다
 * 사라져서 다시 걸어야 하는데, 그때 걸지 말지를 이 표시로 정한다. 기기마다
 * 뜻이 다른 값이라 클라우드 복원에 덮이면 안 된다.
 */
object DailyResetScheduler {
    const val ACTION_RUN = "com.coscene.nyangcoach.DAILY_RESET"

    private const val REQUEST_CODE = 7420
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_ARMED = "daily_reset_armed"

    /** 자정 바로는 기기 시계가 아직 어제로 읽힐 수 있어서 몇 분 둔다. */
    private const val MINUTES_AFTER_MIDNIGHT = 5

    fun arm(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ARMED, true)
            .apply()
        OngoingNudgeScheduler.schedule(context, nextRunAt(), pendingIntent(context))
    }

    fun cancel(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_ARMED)
            .apply()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent(context))
    }

    /** 걸려 있어야 하는 사람이면 다시 건다. 재부팅 뒤와, 알람이 울린 직후에 부른다. */
    fun rearmIfWanted(context: Context) {
        val armed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ARMED, false)
        if (armed) arm(context)
    }

    private fun nextRunAt(): Long {
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, MINUTES_AFTER_MIDNIGHT)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        // 0시~0시 5분 사이에 걸면 오늘 0시 5분이 아직 안 왔다. 그 자리를 쓴다.
        val today = (next.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }
        return if (today.timeInMillis > System.currentTimeMillis()) {
            today.timeInMillis
        } else {
            next.timeInMillis
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailyResetReceiver::class.java).apply {
            action = ACTION_RUN
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
