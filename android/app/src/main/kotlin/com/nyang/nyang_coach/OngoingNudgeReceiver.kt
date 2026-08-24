package com.coscene.nyangcoach

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 예약된 시각에 깨어나 냥냥이를 내보낼지 정한다.
 *
 * 두 번에 나눠 확인한다. 처음에 폰을 보고 있으면 4분 뒤에 한 번 더 보고,
 * 그때도 여전히 보고 있으면 그제서야 내보낸다. 시간을 확인하려고 잠깐 켠 사람과
 * 영상에 빠진 사람을 이 두 번으로 가른다.
 */
class OngoingNudgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> {
                if (OngoingNudgeState.isActive(context) &&
                    (OngoingNudgeState.isEnabled(context) ||
                        OngoingNudgeState.isStartReminder(context) ||
                        OngoingNudgeState.isNextTaskReminder(context))
                ) {
                    OngoingNudgeScheduler.scheduleIn(
                        context,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                }
            }

            else -> handleCheck(context, intent.getStringExtra(OngoingNudgeScheduler.EXTRA_STAGE))
        }
    }

    private fun handleCheck(context: Context, stage: String?) {
        // 그 사이에 완료했거나, 스위치를 껐거나, 권한이 사라졌으면 여기서 끝난다.
        val isStartReminder = OngoingNudgeState.isStartReminder(context)
        val isNextTaskReminder = OngoingNudgeState.isNextTaskReminder(context)
        if ((!isStartReminder && !isNextTaskReminder && !OngoingNudgeState.isEnabled(context)) ||
            !OngoingNudgeState.isActive(context) ||
            !OngoingNudgeState.canDrawOverlays(context)
        ) {
            OngoingNudgeScheduler.cancel(context)
            return
        }

        // "지금 한번 보기"는 사용자가 앱을 나가는 데 몇 초가 걸린다. 그 몇 초를
        // 놓쳤다고 10분 뒤로 미루면 확인할 방법이 없어진다. 잠깐 동안 자주 본다.
        if (stage == OngoingNudgeScheduler.STAGE_TEST) {
            if (OngoingNudgeState.shouldAppearNow(context)) {
                OngoingNudgeState.clearTestWindow(context)
                OngoingNudgeService.show(context)
                return
            }
            if (OngoingNudgeState.isTestWindowOpen(context)) {
                OngoingNudgeScheduler.scheduleIn(
                    context,
                    OngoingNudgeScheduler.TEST_RETRY_MILLIS,
                    OngoingNudgeScheduler.STAGE_TEST,
                )
            }
            return
        }

        // 시작할 시각을 기다리는 중. 이쪽은 두 번에 나눠 확인하지 않는다.
        //
        // 진행 중인 일정은 "잠깐 폰을 켠 건지 빠져 있는 건지"를 갈라야 하지만,
        // 시작할 시각에 폰을 들고 있다면 그것만으로 충분한 신호다. 4분을 더
        // 기다리면 시작할 시각이 이미 지나간 뒤에 나타난다.
        if (isStartReminder) {
            if (OngoingNudgeState.isStartWindowOver(context)) {
                // 오늘은 지나갔다. 밤까지 들고 다니면 알림이 아니라 잔소리가 된다.
                OngoingNudgeState.clear(context)
                OngoingNudgeScheduler.cancel(context)
                return
            }
            if (OngoingNudgeState.shouldAppearNow(context, requireEnabled = false)) {
                OngoingNudgeService.show(context)
            } else {
                OngoingNudgeScheduler.scheduleIn(
                    context,
                    OngoingNudgeScheduler.START_SNOOZE_MILLIS,
                    OngoingNudgeScheduler.STAGE_FIRST,
                )
            }
            return
        }

        // 완료 3시간 뒤 "남은 일정도 시작할까냥?". 매번 조건부터 다시 본다 —
        // 그 사이 다른 일을 시작했거나, 시간이 정해지지 않은 남은 일이 없어졌으면
        // 사용자에게 아무 말 없이 접는다. 미룬 게 아니라 더 물을 이유가 없어진 거라
        // 재촉으로 느껴지면 안 된다.
        if (isNextTaskReminder) {
            if (OngoingNudgeState.isNextTaskWindowOver()) {
                OngoingNudgeState.clear(context)
                OngoingNudgeScheduler.cancel(context)
                return
            }
            val candidate = OngoingNudgeAnswerWriter.findNextTaskCandidate(context)
            if (candidate == null ||
                OngoingNudgeAnswerWriter.isAnyTaskInProgress(context) ||
                OngoingNudgeAnswerWriter.hasAnyTimedRemainingTask(context)
            ) {
                OngoingNudgeState.clear(context)
                OngoingNudgeScheduler.cancel(context)
                return
            }
            // 처음 걸어둘 때와 지금 사이에 다른 일이 먼저 채워졌을 수 있다.
            // 보여줄 거라면 지금 기준으로 가장 앞선 후보로 다시 적어 넣는다.
            OngoingNudgeState.start(context, candidate.first, candidate.second, OngoingNudgeState.KIND_NEXT)
            if (OngoingNudgeState.shouldAppearNow(context, requireEnabled = false)) {
                OngoingNudgeService.show(context)
            } else {
                OngoingNudgeScheduler.scheduleIn(
                    context,
                    OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                    OngoingNudgeScheduler.STAGE_FIRST,
                )
            }
            return
        }

        if (!OngoingNudgeState.shouldAppearNow(context)) {
            // 폰을 안 보고 있다는 뜻이다. 아마 그 일을 하는 중이니 건드리지 않는다.
            OngoingNudgeScheduler.scheduleIn(
                context,
                OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                OngoingNudgeScheduler.STAGE_FIRST,
            )
            return
        }

        if (stage != OngoingNudgeScheduler.STAGE_CONFIRM) {
            OngoingNudgeScheduler.scheduleIn(
                context,
                OngoingNudgeScheduler.CONFIRM_DELAY_MILLIS,
                OngoingNudgeScheduler.STAGE_CONFIRM,
            )
            return
        }

        // 여기가 딴짓 방지 코칭이 실제로 나가는 자리다. 프렌즈는 하루 한
        // 일정까지라, 하루치도 여기서 센다.
        //
        // 시작을 권하는 알림은 위에서 이미 돌아갔다. 제한은 딴짓 방지 코칭에만
        // 걸린다.
        if (!OngoingNudgeState.claimDailyQuota(context)) {
            // 오늘 이 일정에는 더 나가지 않는다. 계속 다시 물어봐야 답이
            // 달라지지 않으므로 예약도 접는다. 앱을 열면 다시 잡힌다.
            OngoingNudgeScheduler.cancel(context)
            return
        }

        OngoingNudgeService.show(context)
    }
}
