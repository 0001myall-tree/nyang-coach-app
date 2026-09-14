package com.coscene.nyangcoach

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/**
 * 틈새 코칭 카드에 적을 한 줄.
 *
 * 문장은 여기서 만들지 않는다. Dart가 앱이 켜져 있을 때 미리 만들어 저장해두고,
 * 여기서는 읽어서 아직 쓸 만한지만 본다.
 *
 * 원래는 카드가 뜨는 순간에 여기서 목록을 읽어 직접 만들었다. 앱이 꺼져 있어도
 * 돌아야 해서 그랬는데, 그러면 어떤 일에 어떤 말을 할지가 Dart와 코틀린에 두 벌
 * 있게 된다 — 한쪽만 고치면 안드로이드와 아이폰이 다른 말을 한다. 아이폰은
 * 알림을 예약할 때 문구가 굳어서 어차피 미리 만들 수밖에 없으므로, 양쪽을 미리
 * 만드는 쪽으로 맞췄다.
 *
 * 미리 만든 문장은 낡을 수 있다. 아침에 만든 "'분기 리포트' 개요 잡을까"를 그
 * 일을 끝낸 오후에 띄우면 엉뚱하다. 그래서 Dart가 고른 일의 id와 만든 날짜를
 * 함께 적어두고, 여기서는 그 둘만 확인한다. 목록 하나만 보면 되므로 판단이
 * 두 벌로 늘지 않는다.
 *
 * 날짜를 따로 보는 이유는, 어제 일이 오늘까지 넘어오면 id가 그대로 살아 있기
 * 때문이다. 앱을 하루 종일 안 연 사람에게 어제 만든 말이 나가게 된다.
 */
object GapCoachingCopy {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_TASKS = "flutter.nyang_tasks"

    /** Dart가 만들어 둔 카드. `GapCoachingService.preparedCardKey`와 같은 이름이다. */
    private const val KEY_CARD = "flutter.gap_coaching_card"

    /** 날짜별 계획 보관함. `DailyResetService.plannedTasksByDateKey`와 같은 이름이다. */
    private const val KEY_PLANNED_BY_DATE = "flutter.nyang_today_tasks_by_date"

    /**
     * Dart가 아직 아무것도 안 만들어 뒀거나, 만들어 둔 것이 낡았을 때.
     *
     * 앱을 한 번도 안 연 채로 시각이 온 경우다. 이름을 부를 수는 없지만 여유
     * 있냐고 묻는 것 자체는 할 만한 말이라, 조용히 넘기지 않고 이걸 띄운다.
     */
    const val FALLBACK = "이따 할 일, 10분만 먼저 해두면 훨씬 가벼워질 거라냥."

    /** 오늘 아무것도 적어두지 않았을 때. */
    const val EMPTY_BODY = "오늘 뭘 할지 아직 안 정했다냥. 10분만 써서 하나만 정해둬도 훨씬 수월해질 거라냥."

    const val BUTTON_DEFAULT = "이따 할 일 바로 보기"
    const val BUTTON_PLAN = "오늘 할 일 정하기"

    /** 카드에 들어갈 한 줄과, 그 아래 버튼에 적을 말. */
    data class Card(val body: String, val buttonLabel: String)

    fun cardFor(context: Context): Card {
        prepared(context)?.let { return it }
        return if (hasAnyRemaining(context) || plannedAhead(context)) {
            Card(FALLBACK, BUTTON_DEFAULT)
        } else {
            Card(EMPTY_BODY, BUTTON_PLAN)
        }
    }

    /**
     * 오늘 하기로 미리 적어둔 것이 있는지.
     *
     * 오늘 목록만 보면 안 된다. 전날 밤에 짜둔 계획은 날짜별 보관함에 들어가
     * 있다가, 그날 앱을 처음 열 때 오늘 목록으로 옮겨진다. 앱을 안 연 채로
     * 카드가 뜨면 계획을 다 짜둔 사람에게 "아직 안 정했다"고 말하게 된다.
     */
    private fun plannedAhead(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PLANNED_BY_DATE, null) ?: return false
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return false
        val planned = json.optJSONArray(today()) ?: return false
        for (i in 0 until planned.length()) {
            val item = planned.optJSONObject(i) ?: continue
            if (!item.optBoolean("done", false)) return true
        }
        return false
    }

    /** Dart가 만들어 둔 카드. 없거나 가리키는 일이 이미 끝났으면 null. */
    private fun prepared(context: Context): Card? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_CARD, null) ?: return null
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        val body = json.optString("body", "").trim()
        if (body.isBlank()) return null

        // 오늘 만든 것만 쓴다. 날짜가 없는 건 이 확인이 생기기 전에 만든
        // 카드라, 낡은 것으로 본다.
        if (json.optString("date", "") != today()) return null

        val taskId = json.optString("taskId", "")
        if (taskId.isNotBlank() && !isStillPending(context, taskId)) return null

        val button = json.optString("button", "").ifBlank { BUTTON_DEFAULT }
        return Card(body, button)
    }

    /** 오늘 날짜. Dart의 `_dateKey`와 같은 모양이다. */
    private fun today(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /** 그 일이 아직 남아 있는지. 목록에서 사라졌으면 남은 것으로 보지 않는다. */
    private fun isStillPending(context: Context, taskId: String): Boolean {
        val tasks = tasksArray(context) ?: return false
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optString("id", "") != taskId) continue
            if (item.optBoolean("done", false)) return false
            if (item.optBoolean("inProgress", false)) return false
            return true
        }
        return false
    }

    /** 아직 안 끝낸 일이 하나라도 있는지. 약속도 센다. */
    private fun hasAnyRemaining(context: Context): Boolean =
        countTasks(context).first > 0

    /**
     * 오늘 할 일을 다 끝냈는지.
     *
     * 다 한 사람에게 여유 있냐고 묻는 것은 칭찬이 아니라 잔소리다. 그날 그 시각은
     * 그냥 지나간다. 아무것도 적어두지 않은 사람과는 구분해야 한다 — 그쪽에는
     * 하나 정해두자고 권할 말이 있다.
     *
     * 이건 문장이 아니라 "지금 띄울지"를 정하는 자리라 여기 남는다. 미리 정해둘
     * 수 없고 그 시각의 목록을 봐야 한다.
     */
    fun isDayFinished(context: Context): Boolean {
        val (remaining, done) = countTasks(context)
        return remaining == 0 && done > 0
    }

    /** 남은 개수와 끝낸 개수. */
    private fun countTasks(context: Context): Pair<Int, Int> {
        val tasks = tasksArray(context) ?: return 0 to 0
        var remaining = 0
        var done = 0
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) done++ else remaining++
        }
        return remaining to done
    }

    private fun tasksArray(context: Context): JSONArray? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_TASKS, null) ?: return null
        return runCatching { JSONArray(raw) }.getOrNull()
    }
}
