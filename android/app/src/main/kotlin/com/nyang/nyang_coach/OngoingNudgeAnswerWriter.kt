package com.coscene.nyangcoach

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 냥냥이 카드에서 고른 답을 그 자리에서 할 일 데이터에 적어 넣는다.
 *
 * 원래는 쪽지만 남기고 앱이 나중에 읽어가게 했는데, 며칠씩 앱을 안 여는 사람은
 * 그동안 완료 표시가 안 채워진 채로 남는다. 완료 표시를 도우려고 만든 기능이
 * 정작 그걸 미루게 두면 안 된다.
 *
 * 그래서 눈에 보이는 것은 여기서 바로 적는다 — 할 일의 완료 표시, 핵심 일정,
 * 습관 도장. 그날 기록의 개수처럼 세어봐야 아는 것은 손대지 않는다. 주 n회 습관이
 * 오늘 세는 대상인지 같은 판단이 필요한데 여기서는 알 수 없어서, 어림으로 적으면
 * 오히려 틀린 숫자가 남는다. 그 몫은 앱이 켜질 때 TaskCompletionService가 맡는다.
 *
 * 쪽지도 그대로 남긴다. 앱이 열리면 그 서비스가 한 번 더 정확히 훑는다.
 */
object OngoingNudgeAnswerWriter {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_TASKS = "flutter.nyang_tasks"
    private const val KEY_CORE_TASKS = "flutter.nyang_core_tasks"
    private const val KEY_HABIT_LOGS = "flutter.nyang_habit_logs"
    /**
     * 저장소가 바뀐 시각.
     *
     * 앱이 백그라운드에 떠 있는 채로 여기서 데이터를 고칠 수 있다. 화면이 메모리에
     * 든 옛 목록을 그대로 저장하면 방금 한 완료가 되돌아가므로, 돌아올 때 다시
     * 읽으라고 표시를 남긴다. Dart의 TaskCompletionService가 같은 키를 본다.
     */
    private const val KEY_CHANGED_AT = "flutter.task_store_changed_at"

    /** 지금 담겨 있는 할 일이 어느 날의 것인지. 자정을 넘겨도 앱을 열기 전까지는 그 전날이다. */
    private const val KEY_LAST_DATE = "flutter.nyang_last_date"

    private fun markStoreChanged(prefs: android.content.SharedPreferences) {
        prefs.edit().putString(KEY_CHANGED_AT, isoOf(Date())).commit()
    }

    fun apply(context: Context, taskId: String, done: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return

        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return
        var target: JSONObject? = null
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.opt("id")?.toString() == taskId) {
                target = item
                break
            }
        }
        val task = target ?: return
        if (task.optBoolean("done", false)) return

        val now = Date()
        val elapsed = elapsedSecondsOf(task, now)

        task.put("inProgress", false)
        task.remove("runStartedAt")
        task.put("elapsedSeconds", elapsed)
        if (done) {
            task.put("done", true)
            task.put("actualSeconds", elapsed)
            task.put("completedAt", isoOf(now))
        }
        prefs.edit().putString(KEY_TASKS, tasks.toString()).commit()
        markStoreChanged(prefs)

        if (!done) return

        val dateKey = prefs.getString(KEY_LAST_DATE, null) ?: dateOf(now)
        markCoreTaskDone(prefs, taskId, isoOf(now))
        task.opt("habitId")?.toString()?.takeIf { it.isNotBlank() && it != "null" }?.let {
            markHabitDone(prefs, it, dateKey, isoOf(now))
        }
    }

    /**
     * "시작할게"를 그 자리에서 시작으로 적는다.
     *
     * 앱에 들어가 ▶를 누르는 것과 같은 일을 한다. 쌓인 시간은 건드리지 않고
     * 지금부터 도는 구간만 연다 — 멈췄다 다시 시작하는 경우에도 이어서 흐른다.
     */
    fun markStarted(context: Context, taskId: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return

        var target: JSONObject? = null
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.opt("id")?.toString() == taskId) {
                target = item
                break
            }
        }
        val task = target ?: return
        if (task.optBoolean("done", false)) return
        if (task.optBoolean("inProgress", false)) return

        val now = isoOf(Date())
        task.put("inProgress", true)
        task.put("runStartedAt", now)
        // 이 일을 맨 처음 시작한 시각은 한 번만 적는다. 저녁에 "시작해두고 멈춘
        // 것 같은데"를 물을 때 방금 누른 시각을 보게 되면 안 된다.
        if (task.optString("inProgressAt", "").isBlank()) {
            task.put("inProgressAt", now)
        }
        // 멈춘 시각은 다시 도는 순간 뜻을 잃는다. 남겨두면 다음에 또 멈췄을 때
        // "멈춘 지 3시간" 카드가 이번이 아니라 저번 것으로 착각할 수 있다.
        task.remove("pausedAt")
        prefs.edit().putString(KEY_TASKS, tasks.toString()).commit()
        markStoreChanged(prefs)
    }

    /**
     * 시간이 정해지지 않은, 아직 손대지 않은 다음 일.
     *
     * "냥이랑 남은 일정도 시작할까냥?" 카드가 매번 다시 검사하는 조건이다. 목록
     * 순서상 가장 앞의 것 하나만 본다 — 여러 개를 한꺼번에 권하면 그중 뭘 먼저
     * 해야 하는지 다시 고르게 만드는 셈이라, 고르는 일을 대신 해주지 못한다.
     */
    fun findNextTaskCandidate(context: Context): Pair<String, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return null
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return null

        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optString("category", "") == "schedule") continue
            if (item.optBoolean("done", false)) continue
            if (item.optBoolean("inProgress", false)) continue
            if (item.optInt("elapsedSeconds", 0) > 0) continue
            val timeStart = item.optString("timeStart", "")
            if (timeStart.isNotBlank()) continue
            val id = item.opt("id")?.toString() ?: continue
            return id to item.optString("text", "")
        }
        return null
    }

    /** 지금 도는 중인 일이 있는지. 있으면 다음 일 카드는 뜨지 않는다. */
    fun isAnyTaskInProgress(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return false
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return false
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("inProgress", false)) return true
        }
        return false
    }

    /**
     * 시작해뒀다 지금은 멈춰 있는 일.
     *
     * "'일정명' 하다가 멈췄네. 다시 시작할까?" 카드가 매번 다시 검사하는 조건이다.
     * [findNextTaskCandidate]와 달리 시간이 정해졌는지는 안 본다 — 이미 손댄
     * 일이라, 다른 시간대 약속이 있어도 잠깐 다시 붙잡을지는 물어볼 만하다.
     */
    fun findResumeCandidate(context: Context): Pair<String, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return null
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return null

        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) continue
            if (item.optBoolean("inProgress", false)) continue
            if (item.optInt("elapsedSeconds", 0) <= 0) continue
            val id = item.opt("id")?.toString() ?: continue
            return id to item.optString("text", "")
        }
        return null
    }

    /**
     * 아직 안 끝난 일 중에 시간이 정해진 게 하나라도 있는지.
     *
     * 있으면 다음 일 카드는 뜨지 않는다. 곧 있을 약속을 앞두고 "다른 것도
     * 시작할까냥?"을 얹으면 정작 지켜야 할 시각에 마음을 못 쓰게 만든다.
     */
    fun hasAnyTimedRemainingTask(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return false
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return false
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) continue
            if (item.optString("timeStart", "").isNotBlank()) return true
        }
        return false
    }

    /**
     * 마지막으로 무언가를 끝낸 지 몇 분 지났는지. 끝낸 게 없으면 null.
     *
     * 틈새 코칭이 본다. 방금 하나를 끝낸 사람의 여유는 이미 벌어둔 여유라,
     * 거기에 대고 또 무언가를 권하지 않는다.
     */
    fun minutesSinceLastCompletion(context: Context): Long? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return null
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return null

        var latest = 0L
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (!item.optBoolean("done", false)) continue
            val at = parseIso(item.optString("completedAt", "")) ?: continue
            if (at > latest) latest = at
        }
        if (latest == 0L) return null
        return (System.currentTimeMillis() - latest) / 60_000L
    }

    /**
     * 시간이 정해진 일정이 지금 앞뒤로 가까이 있는지.
     *
     * [beforeMinutes]는 지나간 쪽, [afterMinutes]는 다가오는 쪽이다. 지켜야 할
     * 시각을 앞두고 "여유 있냐"고 물으면, 정작 그 시각에 마음을 못 쓰게 만든다.
     *
     * 앞뒤로 넉넉하게 두 시간씩 본다. 좁게 잡았다가 약속을 앞둔 사람에게 한 번
     * 잘못 나가는 쪽이, 여유 있는 날 한 번 걸러지는 쪽보다 훨씬 나쁘다.
     */
    fun hasTimedTaskNear(
        context: Context,
        beforeMinutes: Long = 120L,
        afterMinutes: Long = 120L,
    ): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return false
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return false

        val now = java.util.Calendar.getInstance()
        val nowMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
            now.get(java.util.Calendar.MINUTE)
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) continue
            val pieces = item.optString("timeStart", "").split(":")
            if (pieces.size != 2) continue
            val hour = pieces[0].toIntOrNull() ?: continue
            val minute = pieces[1].toIntOrNull() ?: continue
            val diff = nowMinutes - (hour * 60 + minute)
            if (diff in 0..beforeMinutes.toInt()) return true
            if (diff < 0 && -diff <= afterMinutes.toInt()) return true
        }
        return false
    }

    /**
     * Dart가 적은 시각 문자열을 읽는다.
     *
     * Dart 쪽은 마이크로초까지 적을 때가 있는데, 밀리초까지만 아는 형식으로
     * 그대로 읽으면 몇 분씩 밀린 시각이 나온다. 아는 자리까지만 자른다.
     */
    private fun parseIso(raw: String): Long? {
        if (raw.isBlank()) return null
        val trimmed = if (raw.length > 23) raw.substring(0, 23) else raw
        return runCatching { isoFormat().parse(trimmed)?.time }.getOrNull()
    }

    /** 쌓인 시간 + 지금 돌고 있는 구간. */
    private fun elapsedSecondsOf(task: JSONObject, now: Date): Int {
        var elapsed = task.optInt("elapsedSeconds", 0)
        val runStartedAt = task.optString("runStartedAt", "")
        if (runStartedAt.isNotBlank()) {
            val started = runCatching { isoFormat().parse(runStartedAt) }.getOrNull()
            if (started != null) {
                val ran = ((now.time - started.time) / 1000).toInt()
                if (ran > 0) elapsed += ran
            }
        }
        return elapsed
    }

    private fun markCoreTaskDone(
        prefs: android.content.SharedPreferences,
        taskId: String,
        completedAt: String,
    ) {
        val raw = prefs.getString(KEY_CORE_TASKS, null) ?: return
        val list = runCatching { JSONArray(raw) }.getOrNull() ?: return
        var changed = false
        for (i in 0 until list.length()) {
            val item = list.optJSONObject(i) ?: continue
            if (item.opt("id")?.toString() != taskId) continue
            item.put("done", true)
            item.put("completedAt", completedAt)
            changed = true
        }
        if (changed) prefs.edit().putString(KEY_CORE_TASKS, list.toString()).commit()
    }

    private fun markHabitDone(
        prefs: android.content.SharedPreferences,
        habitId: String,
        dateKey: String,
        completedAt: String,
    ) {
        val logs = runCatching {
            JSONObject(prefs.getString(KEY_HABIT_LOGS, null) ?: "{}")
        }.getOrNull() ?: return
        val forHabit = logs.optJSONObject(habitId) ?: JSONObject()
        if (forHabit.has(dateKey)) return
        forHabit.put(
            dateKey,
            JSONObject().apply {
                put("done", true)
                put("status", "done")
                put("completedAt", completedAt)
            },
        )
        logs.put(habitId, forHabit)
        prefs.edit().putString(KEY_HABIT_LOGS, logs.toString()).commit()
    }

    private fun isoFormat() =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)

    private fun isoOf(date: Date) = isoFormat().format(date)

    private fun dateOf(date: Date) =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)
}
