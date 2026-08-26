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

    /** 지금 맡고 있는 것이 어떤 일인지. [KIND_ONGOING], [KIND_NEXT], [KIND_RESUME] 중 하나. */
    private const val KEY_KIND = "flutter.ongoing_nudge_kind"

    /** 이미 시작한 일정을 지켜보는 중. */
    const val KIND_ONGOING = "ongoing"

    /**
     * 방금 하나를 끝냈고, 시간이 정해지지 않은 다음 일이 남아 있어 다시 부르는 중.
     *
     * 마스터 플랜 전용. 완료 3시간 뒤 한 번, 그래도 미루면 22시까지 2시간마다
     * 다시 본다. 매번 [OngoingNudgeAnswerWriter.findNextTaskCandidate]로 조건을
     * 다시 검사해서, 그 사이 다른 일을 시작했거나 남은 일이 없어지면 조용히 접는다.
     */
    const val KIND_NEXT = "next"

    /**
     * 시작해뒀다 멈춘 일이 그 상태로 오래 있어 다시 부르는 중.
     *
     * 마스터 플랜 전용. 멈춘 지 3시간 뒤 한 번, 그래도 미루면 22시까지 2시간마다
     * 다시 본다. [KIND_NEXT]와 같은 조건 재검사 방식을 쓰지만, 대상이 "시간이
     * 정해지지 않은 새 일"이 아니라 "이미 손댄 그 일"이라는 점이 다르다.
     */
    const val KIND_RESUME = "resume"

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

    fun isNextTaskReminder(context: Context): Boolean = kind(context) == KIND_NEXT

    fun isResumeReminder(context: Context): Boolean = kind(context) == KIND_RESUME

    /**
     * 도는 일도, 시작을 기다리는 일도 아닌 "말 걸어보는" 쪽인지.
     *
     * [KIND_NEXT]와 [KIND_RESUME]는 서로의 자리를 자유롭게 넘겨받는다 — 둘 다
     * 급한 일이 아니라, 나중에 걸린 쪽이 이기면 그만이다. 대신 진짜 도는
     * 일([KIND_ONGOING])이 이 자리를 쓰고 있으면 절대 넘겨받지 않는다.
     * 시작을 기다리는 일은 [isStartActive]가 보는 별도 자리라 여기와는 무관하다.
     */
    fun isIdleNudge(context: Context): Boolean =
        isNextTaskReminder(context) || isResumeReminder(context)

    /** 22시가 넘으면 다음 일·재개 권하는 것도 멈춘다. 밤까지 이어지면 잔소리가 된다. */
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

    fun clear(context: Context) {
        prefs(context).edit()
            .remove(KEY_TASK_ID)
            .remove(KEY_TASK_TEXT)
            .remove(KEY_KIND)
            .commit()
    }

    // ── 시작 시각을 기다리는 자리 (독립 슬롯) ──────────────────────
    //
    // 도는 일정([KIND_ONGOING])이나 말 걸어보는 자리([KIND_NEXT]/[KIND_RESUME])와
    // 완전히 별도로 관리한다. 진행 중인 일정이 있어도 다른 일정의 시작 시각은
    // 그대로 기다려야 하고, 그 반대도 마찬가지라 자리를 하나 더 둔다. 알람도
    // [OngoingNudgeScheduler]에서 별도 요청 코드로 예약된다.

    private const val KEY_START_TASK_ID = "ongoing_nudge_start_task_id"
    private const val KEY_START_TASK_TEXT = "ongoing_nudge_start_task_text"

    fun startTaskId(context: Context): String? =
        prefs(context).getString(KEY_START_TASK_ID, null)?.takeIf { it.isNotBlank() }

    fun startTaskText(context: Context): String =
        prefs(context).getString(KEY_START_TASK_TEXT, null).orEmpty()

    fun isStartActive(context: Context): Boolean = startTaskId(context) != null

    fun setStartTask(context: Context, taskId: String, taskText: String) {
        prefs(context).edit()
            .putString(KEY_START_TASK_ID, taskId)
            .putString(KEY_START_TASK_TEXT, taskText)
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

    fun clearStart(context: Context) {
        prefs(context).edit()
            .remove(KEY_START_TASK_ID)
            .remove(KEY_START_TASK_TEXT)
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

    // ── 틈새 코칭 자리 (독립 슬롯) ────────────────────────────
    //
    // 하는 일이 나머지와 반대다. 저쪽은 시작한 일에서 새어 나갔을 때 부르지만,
    // 이쪽은 아무것도 안 하고 있을 때 한 마디만 건넨다. 그래서 일정을 붙들지
    // 않고, 시각과 "오늘 지나갔는지"만 있으면 된다.

    /** 켜고 끄기와 시각. 모닝콜처럼 기기를 바꿔도 따라오는 사용자 설정이다. */
    private const val KEY_GAP_ENABLED = "flutter.nyang_gap_coaching_enabled"
    private const val KEY_GAP_TIMES = "flutter.nyang_gap_coaching_times"

    /** 그 슬롯이 오늘 이미 지나갔는지. 이 기기에서만 뜻이 있어 접두어가 없다. */
    private const val KEY_GAP_FIRED_PREFIX = "gap_coaching_fired_"

    /** 틈새 냥냥이가 실제로 나간 시각. 지나갔지만 걸러진 경우와 구분한다. */
    private const val KEY_GAP_SHOWN_AT = "gap_coaching_shown_at"

    /**
     * 지금 이 기기에서 틈새 코칭을 내보내도 되는 등급·설정인지.
     *
     * 마스터 전용이다. 앱이 꺼진 사이에 판단해야 해서 사용자 정보를 읽을 수
     * 없으므로, 딴짓 방지 코칭이 이미 쓰고 있는 등급 결론을 그대로 본다.
     */
    fun isGapEnabled(context: Context): Boolean {
        val prefs = prefs(context)
        return prefs.getBoolean(KEY_GAP_ENABLED, false) &&
            prefs.getBoolean(KEY_UNLIMITED, false)
    }

    /** 설정된 시각들. "10:30,15:30" 형식을 시·분 쌍으로 읽는다. */
    fun gapTimes(context: Context): List<Pair<Int, Int>> {
        val raw = prefs(context).getString(KEY_GAP_TIMES, null).orEmpty()
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { part ->
            val pieces = part.trim().split(":")
            if (pieces.size != 2) return@mapNotNull null
            val hour = pieces[0].toIntOrNull() ?: return@mapNotNull null
            val minute = pieces[1].toIntOrNull() ?: return@mapNotNull null
            if (hour !in 0..23 || minute !in 0..59) return@mapNotNull null
            hour to minute
        }.take(OngoingNudgeScheduler.GAP_SLOT_COUNT)
    }

    /**
     * 오늘 그 슬롯이 이미 지나갔다고 적는다.
     *
     * 실제로 나갔든, 조건에 걸려 조용히 넘어갔든 똑같이 적는다. 무시해도 다시
     * 부르지 않기로 한 기능이라 둘을 구분할 이유가 없다.
     */
    fun markGapFired(context: Context, slot: Int) {
        prefs(context).edit()
            .putString(KEY_GAP_FIRED_PREFIX + slot, todayKey())
            .commit()
    }

    fun didGapFireToday(context: Context, slot: Int): Boolean =
        prefs(context).getString(KEY_GAP_FIRED_PREFIX + slot, null) == todayKey()

    /**
     * 지금 틈새 코칭을 내보내도 되는 상황인가.
     *
     * 화면이 꺼져 있으면 아무도 보지 못하고, 냥냥코치를 보고 있으면 앱 안에서
     * 이미 할 일이 눈앞에 있다. 둘 다 오늘 그 시각은 그냥 지나간다.
     */
    fun shouldAppearNowForGap(context: Context): Boolean =
        isGapEnabled(context) &&
            canDrawOverlays(context) &&
            isScreenOn(context) &&
            !isAppForeground(context)

    /**
     * 진짜 도는 일정이 이 자리를 쓰고 있는지.
     *
     * 도는 일정은 틈새 코칭보다 앞선다 — 이미 손을 대고 있는 사람에게 여유
     * 있냐고 물을 일이 아니다. 반대로 "다음 일 시작할까"·"멈춘 일 다시
     * 시작할까"([KIND_NEXT]/[KIND_RESUME])는 틈새 코칭에 자리를 내준다.
     * 그쪽은 두 시간 뒤에 다시 물어도 그만이지만, 틈새 코칭은 정해둔 그 시각을
     * 놓치면 그날치가 사라진다.
     */
    fun isGapSlotTaken(context: Context): Boolean =
        isActive(context) && !isIdleNudge(context)

    /** 틈새 냥냥이가 방금 나갔다고 적는다. 실제로 화면에 붙는 자리에서만 부른다. */
    fun markGapShown(context: Context) {
        prefs(context).edit()
            .putLong(KEY_GAP_SHOWN_AT, System.currentTimeMillis())
            .commit()
    }

    /**
     * 틈새 코칭이 나간 지 얼마 안 됐는지.
     *
     * 방금 "여유 있으면 조금 건드려볼래?" 하고 물어놓고 몇 시간 안에 "남은
     * 일정도 시작할까?"를 또 얹으면, 한 번의 제안이 두 번의 재촉이 된다.
     */
    fun isWithinGapAfterglow(context: Context, hours: Int = 3): Boolean {
        val at = prefs(context).getLong(KEY_GAP_SHOWN_AT, 0L)
        if (at <= 0L) return false
        return System.currentTimeMillis() - at < hours * 60L * 60_000L
    }

    /**
     * 지금이 틈새 코칭 시각 언저리인지.
     *
     * "다음 일"·"멈춘 일" 카드가 이걸 보고 비켜준다. 앞뒤로 넉넉히 두 시간을
     * 본다 — 시간 지정 일정을 피하는 폭과 같다.
     */
    fun isNearGapSlot(context: Context, withinMinutes: Int = 120): Boolean {
        if (!isGapEnabled(context)) return false
        val times = gapTimes(context)
        if (times.isEmpty()) return false
        val now = java.util.Calendar.getInstance()
        val nowMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
            now.get(java.util.Calendar.MINUTE)
        return times.any { (hour, minute) ->
            kotlin.math.abs(nowMinutes - (hour * 60 + minute)) <= withinMinutes
        }
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

    /**
     * 시작 시각 자리가 지금 냥냥이를 내보내도 되는 상황인가.
     *
     * 딴짓 방지 스위치([isEnabled])와 무관하고, 이중 확인도 거치지 않는다 —
     * [OngoingNudgeReceiver]가 첫 확인에서 바로 내보낸다.
     */
    fun shouldAppearNowForStart(context: Context): Boolean =
        isStartActive(context) &&
            canDrawOverlays(context) &&
            isScreenOn(context) &&
            !isAppForeground(context)
}
