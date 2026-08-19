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
 * 그래서 여기서는 눈에 보이는 것부터 먼저 적는다 — 할 일의 완료 표시, 핵심 일정,
 * 습관 도장, 그날 기록의 숫자. 개수를 정확히 다시 세는 일(주간 습관이 오늘 세는
 * 대상인지 같은 판단)은 앱이 열릴 때 제자리를 찾으므로 여기서는 어림으로 둔다.
 * 쪽지도 그대로 남겨서, 앱이 열리면 정식 경로가 한 번 더 훑는다.
 */
object OngoingNudgeAnswerWriter {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_TASKS = "flutter.nyang_tasks"
    private const val KEY_CORE_TASKS = "flutter.nyang_core_tasks"
    private const val KEY_HABIT_LOGS = "flutter.nyang_habit_logs"
    private const val KEY_HISTORY = "flutter.nyang_history"

    /** 지금 담겨 있는 할 일이 어느 날의 것인지. 자정을 넘겨도 앱을 열기 전까지는 그 전날이다. */
    private const val KEY_LAST_DATE = "flutter.nyang_last_date"

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

        if (!done) return

        val dateKey = prefs.getString(KEY_LAST_DATE, null) ?: dateOf(now)
        markCoreTaskDone(prefs, taskId, isoOf(now))
        task.opt("habitId")?.toString()?.takeIf { it.isNotBlank() && it != "null" }?.let {
            markHabitDone(prefs, it, dateKey, isoOf(now))
        }
        bumpHistoryRecord(prefs, dateKey, task.optString("text", ""))
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

    /**
     * 그날 기록의 완료 개수를 하나 올린다.
     *
     * 기록 탭과 코치가 보는 "연속 달성"이 이 숫자에서 나온다. 정확한 재계산은
     * 앱이 열릴 때 하고, 여기서는 하루가 통째로 실패로 남는 것만 막는다.
     */
    private fun bumpHistoryRecord(
        prefs: android.content.SharedPreferences,
        dateKey: String,
        taskText: String,
    ) {
        val raw = prefs.getString(KEY_HISTORY, null) ?: return
        val history = runCatching { JSONArray(raw) }.getOrNull() ?: return
        for (i in 0 until history.length()) {
            val record = history.optJSONObject(i) ?: continue
            if (record.optString("date") != dateKey) continue

            val entries = record.optJSONArray("tasks")
            if (entries != null && taskText.isNotBlank()) {
                for (j in 0 until entries.length()) {
                    val entry = entries.optJSONObject(j) ?: continue
                    if (entry.optString("text") != taskText) continue
                    if (entry.optBoolean("done", false)) return
                    entry.put("done", true)
                    break
                }
            }

            val total = record.optInt("totalCount", 0)
            val doneCount = record.optInt("doneCount", 0) + 1
            record.put("doneCount", if (total > 0) minOf(doneCount, total) else doneCount)
            record.put("success", true)
            record.put("updatedAt", isoOf(Date()))
            prefs.edit().putString(KEY_HISTORY, history.toString()).commit()
            return
        }
    }

    private fun isoFormat() =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)

    private fun isoOf(date: Date) = isoFormat().format(date)

    private fun dateOf(date: Date) =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)
}
