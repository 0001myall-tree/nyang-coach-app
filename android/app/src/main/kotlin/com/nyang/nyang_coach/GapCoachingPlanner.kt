package com.coscene.nyangcoach

import android.content.Context
import java.util.Calendar

/**
 * 틈새 코칭 시각을 알람으로 옮긴다.
 *
 * 설정 자체는 Flutter가 저장하고, 여기서는 그 시각들을 읽어 예약만 다시 건다.
 * 앱이 켜질 때, 설정을 바꿀 때, 폰을 다시 켰을 때, 그리고 한 슬롯이 지나간
 * 직후에 불린다.
 */
object GapCoachingPlanner {
    /** 저장된 시각대로 오늘 남은 몫과 내일 몫을 다시 건다. */
    fun reschedule(context: Context) {
        cancelAll(context)
        if (!OngoingNudgeState.isGapEnabled(context)) return

        val times = OngoingNudgeState.gapTimes(context)
        val now = System.currentTimeMillis()
        times.forEachIndexed { slot, (hour, minute) ->
            val today = atToday(hour, minute, daysAhead = 0)
            val alreadyPassed = today <= now ||
                OngoingNudgeState.didGapFireToday(context, slot)
            val triggerAt = if (alreadyPassed) {
                atToday(hour, minute, daysAhead = 1)
            } else {
                today
            }
            OngoingNudgeScheduler.scheduleGapAt(context, triggerAt, slot)
        }
    }

    /** 방금 지나간 슬롯을 내일 같은 시각으로 옮겨 건다. */
    fun scheduleTomorrow(context: Context, slot: Int) {
        if (!OngoingNudgeState.isGapEnabled(context)) return
        val times = OngoingNudgeState.gapTimes(context)
        val time = times.getOrNull(slot) ?: return
        OngoingNudgeScheduler.scheduleGapAt(
            context,
            atToday(time.first, time.second, daysAhead = 1),
            slot,
        )
    }

    fun cancelAll(context: Context) {
        for (slot in 0 until OngoingNudgeScheduler.GAP_SLOT_COUNT) {
            OngoingNudgeScheduler.cancelGap(context, slot)
        }
    }

    private fun atToday(hour: Int, minute: Int, daysAhead: Int): Long =
        Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, daysAhead)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
}
