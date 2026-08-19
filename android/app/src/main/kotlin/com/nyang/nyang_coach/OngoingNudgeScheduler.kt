package com.coscene.nyangcoach

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 냥냥이가 나갈 시각을 예약한다.
 *
 * 계속 켜두고 감시하지 않는다. 정해진 시각에 한 번 깨어나 "지금 폰을 보고 있나"만
 * 확인하고, 아니면 다시 자러 간다. 정확할 필요가 없는 알람이라 배터리에 유리한
 * 느슨한 예약을 쓴다.
 */
object OngoingNudgeScheduler {
    const val ACTION_CHECK = "com.coscene.nyangcoach.ONGOING_NUDGE_CHECK"
    const val EXTRA_STAGE = "stage"

    /** 시작 후 처음 확인하는 자리. */
    const val STAGE_FIRST = "first"

    /** 폰을 잠깐 켠 건지, 계속 보고 있는 건지 가르는 두 번째 확인. */
    const val STAGE_CONFIRM = "confirm"

    private const val REQUEST_CODE = 7401

    /** 시작하고 30분은 아무것도 하지 않는다. */
    const val FIRST_DELAY_MILLIS = 30L * 60_000L

    /** 화면을 켠 뒤에도 계속 보고 있는지 다시 볼 때까지. */
    const val CONFIRM_DELAY_MILLIS = 4L * 60_000L

    /** 지금은 때가 아닐 때(화면 꺼짐, 앱 안) 다시 볼 때까지. */
    const val RETRY_DELAY_MILLIS = 10L * 60_000L

    /** 한 번 나갔다 들어온 뒤 다음 등장까지. */
    const val NEXT_ROUND_DELAY_MILLIS = 60L * 60_000L

    /** 아무도 누르지 않아도 스스로 사라지기까지. */
    const val VISIBLE_MILLIS = 15L * 60_000L

    fun scheduleIn(context: Context, delayMillis: Long, stage: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = System.currentTimeMillis() + delayMillis
        val intent = pendingIntent(context, stage)

        // 느슨한 예약은 절전 중인 기기에서 한참 뒤에야 울리거나 아예 묻힌다.
        // 국내 안드로이드는 사실상 삼성이고 앱 절전이 기본으로 켜져 있어서,
        // 30분 뒤에 나가야 할 냥냥이가 두 시간 뒤에 나가는 일이 생긴다.
        // 앱이 이미 정확한 알람 권한을 갖고 있으니 그걸 쓴다.
        val canBeExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (canBeExact) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent)
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent(context, STAGE_FIRST))
    }

    private fun pendingIntent(context: Context, stage: String): PendingIntent {
        val intent = Intent(context, OngoingNudgeReceiver::class.java).apply {
            action = ACTION_CHECK
            putExtra(EXTRA_STAGE, stage)
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
