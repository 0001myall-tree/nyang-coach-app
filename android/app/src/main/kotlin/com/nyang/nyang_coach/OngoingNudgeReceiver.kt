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
    companion object {
        /** 확인용으로 부른 차례를 다시 보기까지. */
        private const val ACTIVE_TEST_RETRY_MILLIS = 4_000L

        /** 알람이 늦게 울린 만큼은 때가 된 것으로 본다. */
        private const val ACTIVE_DUE_SLACK_MILLIS = 60_000L

        /** 화면이 꺼져 있어 못 띄운 차례를 다시 들여다보는 간격. */
        private const val ACTIVE_SCREEN_RETRY_MILLIS = 20 * 60_000L
    }

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
                // 적극 코칭은 오늘 남은 차례를 다시 건다. 앱을 안 여는 사람이
                // 폰을 한 번 껐다 켰다고 그날 참견이 끝나면 안 된다. 그 사이
                // 끝낸 일은 띄우기 직전에 거른다.
                OngoingNudgeScheduler.rearmActive(context)
            }

            OngoingNudgeScheduler.ACTION_CHECK_START ->
                handleStartCheck(context, intent.getStringExtra(OngoingNudgeScheduler.EXTRA_STAGE))

            OngoingNudgeScheduler.ACTION_CHECK_GAP ->
                handleGapCheck(context, intent.getIntExtra(OngoingNudgeScheduler.EXTRA_SLOT, 0))

            OngoingNudgeScheduler.ACTION_CHECK_ACTIVE -> handleActiveCheck(context)

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
        // 아직 그 시각이 아니다. 여기로 오는 길은 정해둔 시각의 알람만이 아니다 —
        // 재부팅과 앱 교체는 10분 뒤 점검을 걸고, 카드를 띄우다 실패해도 다시
        // 건다. 그 점검이 늦었는지만 보고 이르다는 것은 보지 않으면, 아침 10시
        // 일정이 새벽 1시에 "시작하는 거 잊지 않았지?"로 튀어나온다.
        //
        // 자정 정리가 오늘 목록을 다시 깔면서 만료 시각도 오늘 것으로 새로
        // 쓰기 때문에, 정리가 끝난 뒤의 새벽이 정확히 이 구멍이 열리는 때다.
        if (OngoingNudgeState.isBeforeStartTime(context)) {
            OngoingNudgeScheduler.scheduleStartAt(
                context,
                OngoingNudgeState.startAt(context),
                OngoingNudgeScheduler.STAGE_FIRST,
            )
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
     * 적극 코칭 개입 자리.
     *
     * 오늘 차례는 Dart가 미리 세워뒀다. 여기서는 때가 된 차례가 아직 쓸
     * 만한지만 보고 띄운 뒤, 다음 차례에 알람을 건다 — 무엇을 부를지까지 여기서
     * 정하면 같은 판단이 두 벌이 된다.
     *
     * 못 띄운 차례(화면이 꺼져 있었거나 앱을 보고 있었거나)는 그냥 지나가고
     * 다음 차례를 기다린다. 한꺼번에 밀린 것을 몰아서 띄우지 않는다.
     */
    private fun handleActiveCheck(context: Context) {
        val now = System.currentTimeMillis()
        val queue = OngoingNudgeState.activeQueue(context)
        if (queue.isEmpty()) {
            OngoingNudgeScheduler.cancelActive(context)
            return
        }
        // 알람은 조금 늦게 울리기도 한다. 그 몫만큼은 때가 된 것으로 본다.
        val due = queue.filter { it.atMillis <= now + ACTIVE_DUE_SLACK_MILLIS }
        if (due.isEmpty()) {
            OngoingNudgeScheduler.rearmActive(context)
            return
        }
        // 밀린 차례가 여럿이면 가장 늦은 것 하나만 본다. 그 사이 끝낸 일이면
        // 그 앞의 것으로 내려간다.
        val entry = due.lastOrNull { OngoingNudgeState.isStillWanted(context, it.plan) }

        val screenOff = !OngoingNudgeState.isScreenOn(context)
        val blocked = entry == null ||
            !OngoingNudgeState.canDrawOverlays(context) ||
            screenOff ||
            // 냥냥코치를 보고 있으면 할 일이 이미 눈앞에 있다.
            OngoingNudgeState.isAppForeground(context) ||
            // 붙잡고 있는 일이 있는 사람에게 다른 말을 얹는 것은 방해다.
            OngoingNudgeAnswerWriter.isAnyTaskInProgress(context)

        // "지금 한번 보기"로 부른 차례는 앱을 나갈 때까지 기다린다. 설정에서
        // 누른 참이라 그 순간에는 앱이 화면 앞일 수밖에 없다.
        if (blocked && entry != null && OngoingNudgeState.isActiveTest(context)) {
            OngoingNudgeScheduler.scheduleActiveAt(
                context,
                System.currentTimeMillis() + ACTIVE_TEST_RETRY_MILLIS,
            )
            return
        }

        // 화면이 꺼져 있던 것뿐이면 버리지 않고 켜질 때까지 기다린다. 버리던
        // 때는 그 시각에 마침 폰을 보고 있어야만 떠서, 하루에 몇 번 안 걸렸다.
        // 켜졌다는 신호는 앱이 꺼져 있으면 못 받으므로 20분마다 들여다본다.
        // 다음 차례가 오면 그쪽으로 넘어가고, 밤 시간에는 기다리지 않는다.
        if (screenOff && entry != null &&
            OngoingNudgeState.canDrawOverlays(context) &&
            !OngoingNudgeState.isActiveQuietNow()
        ) {
            val lastDue = due.last().atMillis
            val nextAt = queue.firstOrNull { it.atMillis > lastDue }?.atMillis
            val retryAt = System.currentTimeMillis() + ACTIVE_SCREEN_RETRY_MILLIS
            OngoingNudgeScheduler.scheduleActiveAt(
                context,
                if (nextAt != null && nextAt < retryAt) nextAt else retryAt,
            )
            return
        }

        // 때가 된 차례는 띄우든 못 띄우든 쓴 것으로 치고 다음 차례를 건다.
        // 남겨두면 재부팅 점검이 같은 차례를 또 띄운다.
        OngoingNudgeState.dropActiveUntil(context, due.last().atMillis)
        OngoingNudgeScheduler.rearmActive(context)
        if (blocked || entry == null) return
        OngoingNudgeService.showActive(context, entry.plan)
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

        // 참견하지 않기로 한 요일이다. 알람은 매일 걸려 있고 여기서 거른다 —
        // 예약을 요일마다 다르게 걸면, 요일을 바꿀 때마다 걸린 것과 걸어야 할
        // 것이 어긋나 조용히 빠지는 자리가 생긴다.
        if (!OngoingNudgeState.runsToday(context)) return
        if (!OngoingNudgeState.shouldAppearNowForGap(context)) return
        // 도는 일정이 이 자리를 쓰고 있다. "다음 일"·"멈춘 일" 카드는 반대로
        // 이쪽에 자리를 내주므로 여기서 걸리지 않는다.
        if (OngoingNudgeState.isGapSlotTaken(context)) return
        if (OngoingNudgeAnswerWriter.isAnyTaskInProgress(context)) return
        // 오늘 할 일을 다 끝냈다. 다 한 사람에게 여유 있냐고 묻는 것은 칭찬이
        // 아니라 잔소리다. 아무것도 적어두지 않은 사람은 여기서 걸리지 않는다 —
        // 그쪽에는 하나 정해두자고 권할 말이 있다.
        if (GapCoachingCopy.isDayFinished(context)) return
        // 시각을 정해둔 일정이 지금 그 자리에 걸쳐 있다.
        //
        // 앞뒤 두 시간을 비우고 '방금 끝낸 지 30분'까지 걸렀던 자리다. 둘 다
        // 너무 넓어서, 아침저녁에 시각을 적어둔 사람은 정해둔 틈새 시각이
        // 거의 매번 걸러졌다. Dart 쪽 _gapBlocked와 같은 규칙이다.
        if (OngoingNudgeAnswerWriter.hasTimedTaskNow(context)) return

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

        // 여기가 딴짓 방지 코칭이 실제로 나가는 자리다. 플랜이 끝난 사람에게는
        // 나가지 않는다 — 스위치는 플랜이 있을 때 켜둔 채로 남아 있을 수 있다.
        //
        // 시작을 권하는 알림은 위에서 이미 돌아갔다. 이 확인은 딴짓 방지
        // 코칭에만 걸린다.
        if (!OngoingNudgeState.isPaid(context)) {
            // 계속 다시 물어봐야 답이 달라지지 않으므로 예약도 접는다. 앱을
            // 열면 다시 잡힌다.
            OngoingNudgeScheduler.cancel(context)
            return
        }

        OngoingNudgeService.show(context)
    }
}
