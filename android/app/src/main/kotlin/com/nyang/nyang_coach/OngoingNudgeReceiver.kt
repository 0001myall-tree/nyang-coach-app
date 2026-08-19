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
                if (OngoingNudgeState.isEnabled(context) && OngoingNudgeState.isActive(context)) {
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
        if (!OngoingNudgeState.isEnabled(context) ||
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

        OngoingNudgeService.show(context)
    }
}
