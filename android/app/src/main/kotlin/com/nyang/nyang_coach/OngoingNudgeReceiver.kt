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
                    (OngoingNudgeState.isEnabled(context) || OngoingNudgeState.isIdleNudge(context))
                ) {
                    OngoingNudgeScheduler.scheduleIn(
                        context,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                }
                if (OngoingNudgeState.isStartActive(context)) {
                    OngoingNudgeScheduler.scheduleStartIn(
                        context,
                        OngoingNudgeScheduler.RETRY_DELAY_MILLIS,
                        OngoingNudgeScheduler.STAGE_FIRST,
                    )
                }
                GapCoachingPlanner.reschedule(context)
            }

            OngoingNudgeScheduler.ACTION_CHECK_START ->
                handleStartCheck(context, intent.getStringExtra(OngoingNudgeScheduler.EXTRA_STAGE))

            OngoingNudgeScheduler.ACTION_CHECK_GAP ->
                handleGapCheck(context, intent.getIntExtra(OngoingNudgeScheduler.EXTRA_SLOT, 0))

            else -> handleCheck(context, intent.getStringExtra(OngoingNudgeScheduler.EXTRA_STAGE))
        }
    }

    /**
     * 시작 시각을 기다리는 자리. 진행 중인 일정과 완전히 독립된 알람이라 여기서
     * 따로 처리한다. 두 번에 나눠 확인하지 않는다 — 시작할 시각에 폰을 들고
     * 있다면 그것만으로 충분한 신호고, 4분을 더 기다리면 시각이 지나간 뒤에
     * 나타난다.
     */
    private fun handleStartCheck(context: Context, stage: String?) {
        if (!OngoingNudgeState.isStartActive(context) || !OngoingNudgeState.canDrawOverlays(context)) {
            OngoingNudgeScheduler.cancelStart(context)
            return
        }
        if (OngoingNudgeState.isStartWindowOver(context)) {
            // 오늘은 지나갔다. 밤까지 들고 다니면 알림이 아니라 잔소리가 된다.
            OngoingNudgeState.clearStart(context)
            OngoingNudgeScheduler.cancelStart(context)
            return
        }
        if (OngoingNudgeState.shouldAppearNowForStart(context)) {
            OngoingNudgeService.showStart(context)
        } else {
            OngoingNudgeScheduler.scheduleStartIn(
                context,
                OngoingNudgeScheduler.START_SNOOZE_MILLIS,
                OngoingNudgeScheduler.STAGE_FIRST,
            )
        }
    }

    /**
     * 틈새 코칭 자리. 여유 있어 보이는 시각에 한 마디만 건넨다.
     *
     * 다른 자리와 달리 미루지 않는다. 조건에 걸리면 오늘 그 시각은 그냥
     * 지나간다 — 무시해도 다시 재촉하지 않기로 한 기능이라, 나중에 다시 거는
     * 순간 그 약속이 깨진다. 대신 다음 슬롯과 내일 몫은 그대로 남는다.
     */
    private fun handleGapCheck(context: Context, slot: Int) {
        // 나갔든 걸렀든 오늘 이 슬롯은 지나간 것으로 적는다.
        OngoingNudgeState.markGapFired(context, slot)
        GapCoachingPlanner.scheduleTomorrow(context, slot)

        if (!OngoingNudgeState.shouldAppearNowForGap(context)) return
        // 도는 일정이 이 자리를 쓰고 있다. "다음 일"·"멈춘 일" 카드는 반대로
        // 이쪽에 자리를 내주므로 여기서 걸리지 않는다.
        if (OngoingNudgeState.isGapSlotTaken(context)) return
        if (OngoingNudgeAnswerWriter.isAnyTaskInProgress(context)) return
        // 방금 하나를 끝냈다.
        val sinceDone = OngoingNudgeAnswerWriter.minutesSinceLastCompletion(context)
        if (sinceDone != null && sinceDone in 0L..29L) return
        // 지켜야 할 시각이 앞뒤로 가깝다.
        if (OngoingNudgeAnswerWriter.hasTimedTaskNear(context)) return

        OngoingNudgeService.showGap(context)
    }

    private fun handleCheck(context: Context, stage: String?) {
        // 그 사이에 완료했거나, 스위치를 껐거나, 권한이 사라졌으면 여기서 끝난다.
        val isNextTaskReminder = OngoingNudgeState.isNextTaskReminder(context)
        val isResumeReminder = OngoingNudgeState.isResumeReminder(context)
        if ((!isNextTaskReminder && !isResumeReminder && !OngoingNudgeState.isEnabled(context)) ||
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
            // 틈새 코칭 시각이 가깝거나 방금 나갔으면 이번 차례는 비켜준다.
            // 이쪽은 두 시간 뒤에 다시 물어도 그만이지만, 틈새 코칭은 정해둔 그
            // 시각을 놓치면 그날치가 사라진다. 나간 뒤 세 시간도 피한다 —
            // 한 번의 제안이 두 번의 재촉이 되면 안 된다.
            if (OngoingNudgeState.isNearGapSlot(context) ||
                OngoingNudgeState.isWithinGapAfterglow(context)
            ) {
                OngoingNudgeScheduler.scheduleIn(
                    context,
                    OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS,
                    OngoingNudgeScheduler.STAGE_FIRST,
                )
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

        // 멈춘 지 3시간 뒤 "'일정명' 하다가 멈췄네. 다시 시작할까?". 조건은
        // [isNextTaskReminder] 갈래와 같은 방식으로 매번 다시 본다 — 그 사이
        // 다시 시작했거나(더는 멈춘 상태가 아니거나), 완료했거나, 다른 일을
        // 손댔으면 조용히 접는다.
        if (isResumeReminder) {
            if (OngoingNudgeState.isNextTaskWindowOver()) {
                OngoingNudgeState.clear(context)
                OngoingNudgeScheduler.cancel(context)
                return
            }
            val candidate = OngoingNudgeAnswerWriter.findResumeCandidate(context)
            if (candidate == null || OngoingNudgeAnswerWriter.isAnyTaskInProgress(context)) {
                OngoingNudgeState.clear(context)
                OngoingNudgeScheduler.cancel(context)
                return
            }
            if (OngoingNudgeState.isNearGapSlot(context) ||
                OngoingNudgeState.isWithinGapAfterglow(context)
            ) {
                OngoingNudgeScheduler.scheduleIn(
                    context,
                    OngoingNudgeScheduler.NEXT_TASK_ROUND_MILLIS,
                    OngoingNudgeScheduler.STAGE_FIRST,
                )
                return
            }
            OngoingNudgeState.start(context, candidate.first, candidate.second, OngoingNudgeState.KIND_RESUME)
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
