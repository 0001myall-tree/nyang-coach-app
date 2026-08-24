package com.coscene.nyangcoach

import android.content.Context
import android.os.PowerManager
import android.provider.Settings

/**
 * 진행 중인 일정을 다시 떠올리게 하는 냥냥이의 상태.
 *
 * Flutter와 같은 SharedPreferences 파일을 쓴다. Flutter가 읽어야 하는 값만
 * "flutter." 접두어를 붙이고, 네이티브만 쓰는 값(마지막 위치)은 접두어 없이 둔다.
 * 접두어가 붙은 값은 Flutter 쪽 플러그인이 전부 훑기 때문에 타입이 어긋나면 안 된다
 * (정수는 반드시 Long).
 *
 * 이름은 'nyang_'으로 시작하지 않는다. 그 접두어가 붙은 값은 통째로 클라우드에
 * 올라갔다 내려오는데, 여기 담기는 건 전부 이 기기에서만 뜻이 있는 것들이다.
 */
object OngoingNudgeState {
    private const val PREFS = "FlutterSharedPreferences"

    /** 테스터에게만 켜주는 스위치. 꺼져 있으면 아무것도 하지 않는다. */
    private const val KEY_ENABLED = "flutter.ongoing_nudge_enabled"
    private const val KEY_TASK_ID = "flutter.ongoing_nudge_task_id"
    private const val KEY_TASK_TEXT = "flutter.ongoing_nudge_task_text"
    private const val KEY_RESULT = "flutter.ongoing_nudge_pending_result"

    /** 지금 맡고 있는 것이 어떤 일인지. [KIND_ONGOING] 또는 [KIND_START]. */
    private const val KEY_KIND = "flutter.ongoing_nudge_kind"

    /** 이미 시작한 일정을 지켜보는 중. */
    const val KIND_ONGOING = "ongoing"

    /**
     * 아직 시작하지 않은 일정의 시각을 기다리는 중.
     *
     * 시작한 일을 잊는 것보다 시작 자체를 안 하는 쪽이 훨씬 흔하다. 시작할 시각을
     * 정해두고 그 시각에 폰을 보고 있으면, 그 일정은 대개 그날 시작되지 않는다.
     */
    const val KIND_START = "start"

    /**
     * 방금 하나를 끝냈고, 시간이 정해지지 않은 다음 일이 남아 있어 다시 부르는 중.
     *
     * 마스터 플랜 전용. 완료 3시간 뒤 한 번, 그래도 미루면 22시까지 2시간마다
     * 다시 본다. 매번 [OngoingNudgeAnswerWriter.findNextTaskCandidate]로 조건을
     * 다시 검사해서, 그 사이 다른 일을 시작했거나 남은 일이 없어지면 조용히 접는다.
     */
    const val KIND_NEXT = "next"

    /** 시작을 권하는 것도 이 시각까지만. 네이티브만 쓴다. */
    private const val KEY_START_UNTIL = "ongoing_nudge_start_until"

    /** 냥냥코치가 화면 앞에 있는지. 앱 안에서는 이미 진행 중 카드가 보이므로 나가지 않는다. */
    private const val KEY_APP_FOREGROUND = "flutter.ongoing_nudge_app_foreground"

    /** 그 표시를 남긴 프로세스. 앱이 죽었다 살아나면 번호가 달라진다. */
    private const val KEY_APP_FOREGROUND_PID = "ongoing_nudge_app_foreground_pid"

    /** "지금 한번 보기"를 언제까지 기다려줄지. 네이티브만 쓴다. */
    private const val KEY_TEST_UNTIL = "ongoing_nudge_test_until"

    /** 사용자가 옮겨둔 세로 위치. 네이티브만 쓴다. */
    private const val KEY_POSITION_Y = "ongoing_nudge_position_y"

    /**
     * 마스터 등급인지. Flutter가 적어두고 여기서 읽는다.
     *
     * 앱이 꺼진 사이에 판단해야 해서 사용자 정보를 읽을 수 없다. 결론만 받는다.
     */
    private const val KEY_UNLIMITED = "flutter.ongoing_nudge_unlimited"

    /** 오늘치를 가져간 날짜(yyyy-MM-dd)와 그 일정. Flutter와 같이 본다. */
    private const val KEY_SLOT_DATE = "flutter.ongoing_nudge_slot_date"
    private const val KEY_SLOT_TASK_ID = "flutter.ongoing_nudge_slot_task_id"

    /** 냥냥이가 실제로 나왔는지. 자리만 맡아둔 상태와 구분한다. */
    private const val KEY_SLOT_CONFIRMED = "flutter.ongoing_nudge_slot_confirmed"

    /** 맡아둔 자리의 예정 발동 시각. 여기서는 쓰지 않지만 함께 지운다. */
    private const val KEY_SLOT_FIRES_AT = "flutter.ongoing_nudge_slot_fires_at"

    /**
     * 어떤 코치를 쓰든 화면 밖으로 나가는 얼굴은 냥냥이 하나다.
     * 앱의 상징이고, 다른 앱 위에서는 이게 냥냥코치라는 걸 한눈에 알아야 한다.
     */
    const val IMAGE_ASSET = "flutter_assets/assets/images/cat_nobg.png"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun taskId(context: Context): String? =
        prefs(context).getString(KEY_TASK_ID, null)?.takeIf { it.isNotBlank() }

    fun taskText(context: Context): String =
        prefs(context).getString(KEY_TASK_TEXT, null).orEmpty()

    fun isActive(context: Context): Boolean = taskId(context) != null

    fun kind(context: Context): String =
        prefs(context).getString(KEY_KIND, null).orEmpty().ifBlank { KIND_ONGOING }

    fun isStartReminder(context: Context): Boolean = kind(context) == KIND_START

    fun isNextTaskReminder(context: Context): Boolean = kind(context) == KIND_NEXT

    /** 22시가 넘으면 다음 일 권하는 것도 멈춘다. 밤까지 이어지면 잔소리가 된다. */
    fun isNextTaskWindowOver(): Boolean {
        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        return hour >= 22
    }

    fun start(
        context: Context,
        taskId: String,
        taskText: String,
        kind: String = KIND_ONGOING,
    ) {
        prefs(context).edit()
            .putString(KEY_TASK_ID, taskId)
            .putString(KEY_TASK_TEXT, taskText)
            .putString(KEY_KIND, kind)
            .commit()
    }

    /**
     * 시작을 권하는 일을 언제까지 붙들고 있을지.
     *
     * 놓친 시각을 밤늦게까지 들고 다니면 그건 알림이 아니라 잔소리가 된다.
     */
    fun setStartUntil(context: Context, atMillis: Long) {
        prefs(context).edit().putLong(KEY_START_UNTIL, atMillis).commit()
    }

    fun isStartWindowOver(context: Context): Boolean {
        val until = prefs(context).getLong(KEY_START_UNTIL, 0L)
        return until > 0L && System.currentTimeMillis() > until
    }

    /** 시작을 권하던 일정이 이제 도는 중이 됐다. 지켜보는 쪽으로 넘긴다. */
    fun switchToOngoing(context: Context) {
        prefs(context).edit()
            .putString(KEY_KIND, KIND_ONGOING)
            .remove(KEY_START_UNTIL)
            .commit()
    }

    fun clear(context: Context) {
        prefs(context).edit()
            .remove(KEY_TASK_ID)
            .remove(KEY_TASK_TEXT)
            .remove(KEY_KIND)
            .remove(KEY_START_UNTIL)
            .commit()
    }

    /**
     * 사용자가 카드에서 고른 답. Flutter가 다음에 켜질 때 읽어서 일정에 반영한다.
     * 백그라운드에서 Dart를 깨우지 않고, 이미 쓰고 있는 모닝콜 payload와 같은 방식이다.
     */
    fun writeResult(context: Context, taskId: String, action: String) {
        val json = """{"taskId":"${escape(taskId)}","action":"$action","at":${System.currentTimeMillis()}}"""
        prefs(context).edit().putString(KEY_RESULT, json).commit()
    }

    private fun escape(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    /**
     * 앱이 화면 앞에 있다고 표시한다. 표시를 남긴 프로세스 번호도 함께 적는다.
     */
    fun setAppForeground(context: Context, value: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_APP_FOREGROUND, value)
            .putLong(KEY_APP_FOREGROUND_PID, android.os.Process.myPid().toLong())
            .commit()
    }

    /**
     * 냥냥코치가 지금 화면 앞에 있는지.
     *
     * 표시만 믿으면, 앱이 시스템에 갑자기 종료됐을 때 "앞에 있음"으로 굳어서
     * 그 뒤로 냥냥이가 영영 나가지 못한다. 그래서 표시를 남긴 프로세스가 아직
     * 그 프로세스인지 함께 본다 — 앱이 죽었다 다시 뜨면 번호가 달라지고,
     * 그건 화면 앞에 있지 않다는 뜻이다.
     *
     * 프로세스 중요도로 판단하지 않는다. 알람을 받는 동안에는 우리 프로세스가
     * 잠깐 앞에 있는 것으로 잡혀서, 늘 "앱을 보고 있다"가 되어버린다.
     */
    fun isAppForeground(context: Context): Boolean {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_APP_FOREGROUND, false)) return false
        val markedPid = prefs.getLong(KEY_APP_FOREGROUND_PID, -1L)
        return markedPid == android.os.Process.myPid().toLong()
    }

    fun positionY(context: Context): Int =
        prefs(context).getInt(KEY_POSITION_Y, -1)

    fun savePositionY(context: Context, y: Int) {
        prefs(context).edit().putInt(KEY_POSITION_Y, y).apply()
    }

    fun openTestWindow(context: Context, millis: Long) {
        prefs(context).edit()
            .putLong(KEY_TEST_UNTIL, System.currentTimeMillis() + millis)
            .commit()
    }

    fun isTestWindowOpen(context: Context): Boolean =
        prefs(context).getLong(KEY_TEST_UNTIL, 0L) > System.currentTimeMillis()

    fun clearTestWindow(context: Context) {
        prefs(context).edit().remove(KEY_TEST_UNTIL).commit()
    }

    /**
     * 프렌즈 등급의 하루치를 지금 맡고 있는 일정이 가져간다.
     *
     * 부르는 자리가 곧 냥냥이가 나가는 자리다. 시작할 때가 아니라 여기서 세는
     * 이유는, 시작만 해두고 딴짓하지 않은 일정에 하루치를 잃으면 받아본 적
     * 없는 코칭에 몫을 잃는 셈이기 때문이다.
     *
     * 이미 이 일정이 임자면 그대로 true다. 하루 한 "번"이 아니라 한
     * "일정"이라, 한 번 나온 일정은 그날 내내 30분마다 계속 나온다.
     *
     * 아직 나오지 않은 자리(아이폰 배너 갈래가 맡아두는 미확정 자리)는
     * 빼앗는다. 나오지 못한 자리를 붙들고 있으면 몫이 다음 일정으로 넘어가야
     * 한다는 규칙이 무너진다.
     */
    fun claimDailyQuota(context: Context): Boolean {
        val prefs = prefs(context)
        if (prefs.getBoolean(KEY_UNLIMITED, false)) return true
        val taskId = taskId(context) ?: return false

        val today = todayKey()
        if (prefs.getString(KEY_SLOT_DATE, null) == today) {
            val owner = prefs.getString(KEY_SLOT_TASK_ID, null)
            if (!owner.isNullOrBlank() &&
                owner != taskId &&
                prefs.getBoolean(KEY_SLOT_CONFIRMED, false)
            ) {
                return false
            }
        }

        prefs.edit()
            .putString(KEY_SLOT_DATE, today)
            .putString(KEY_SLOT_TASK_ID, taskId)
            .putBoolean(KEY_SLOT_CONFIRMED, true)
            .remove(KEY_SLOT_FIRES_AT)
            .commit()
        return true
    }

    /** Flutter가 쓰는 날짜 표기와 같아야 한다. */
    private fun todayKey(): String {
        val calendar = java.util.Calendar.getInstance()
        return String.format(
            java.util.Locale.US,
            "%04d-%02d-%02d",
            calendar.get(java.util.Calendar.YEAR),
            calendar.get(java.util.Calendar.MONTH) + 1,
            calendar.get(java.util.Calendar.DAY_OF_MONTH),
        )
    }

    fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** 화면이 켜져 있으면 폰을 보고 있는 중이라고 본다. 꺼져 있으면 건드리지 않는다. */
    fun isScreenOn(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    /** 지금 냥냥이를 내보내도 되는 상황인가. */
    fun shouldAppearNow(context: Context, requireEnabled: Boolean = true): Boolean =
        (!requireEnabled || isEnabled(context)) &&
            isActive(context) &&
            canDrawOverlays(context) &&
            isScreenOn(context) &&
            !isAppForeground(context)
}
