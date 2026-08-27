package com.coscene.nyangcoach

import android.content.Context
import org.json.JSONArray
import java.util.Calendar

/**
 * 틈새 코칭 카드에 적을 한 줄.
 *
 * "이따 할 일"이라고만 하면 아무 일도 떠오르지 않는다. 그 자리에서 이름을 불러줘야
 * 무엇을 10분 앞당길지가 눈앞에 선다. 그래서 오늘 남은 일 중 하나를 골라 이름을
 * 넣고, 그 일에 어울리는 말투를 고른다 — 기획하는 일에 "미리 해두라"고 하면
 * 무엇을 하라는 건지 알 수 없고, 반대로 설거지에 "개요를 생각해두라"고 하면 웃긴다.
 *
 * 고를 일이 없으면 이름 없는 문장으로 돌아간다. 여유 있냐고 묻는 것 자체는
 * 할 일이 없어도 할 만한 말이다.
 */
object GapCoachingCopy {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_TASKS = "flutter.nyang_tasks"

    /** 카드 한 줄에 들어가는 만큼. 넘치면 줄이 늘어나 버튼이 아래로 밀린다. */
    private const val NAME_LIMIT = 14

    /** 남은 일은 있는데 이름을 부를 만한 것이 없을 때. */
    const val FALLBACK = "이따 할 일, 10분만 먼저 해두면 훨씬 가벼워질 거라냥."

    /**
     * 오늘 아무것도 적어두지 않았을 때.
     *
     * 앞당길 대상이 없는 사람에게 "미리 해두라"고 하면 없는 일을 하라는 말이
     * 된다. 이때 도움이 되는 것은 하나 정해두는 쪽이다.
     */
    const val EMPTY_BODY = "오늘 뭘 할지 아직 안 정했다냥. 10분만 써서 하나만 정해둬도 훨씬 수월해질 거라냥."

    const val BUTTON_DEFAULT = "이따 할 일 바로 보기"
    const val BUTTON_PLAN = "오늘 할 일 정하기"

    /** 카드에 들어갈 한 줄과, 그 아래 버튼에 적을 말. */
    data class Card(val body: String, val buttonLabel: String)

    /** 만들기 전에 무엇을 만들지부터 정해야 하는 일. */
    private val CONCEPT_WORDS = listOf(
        "기획", "아이디어", "콘텐츠", "카드뉴스", "디자인", "영상", "캠페인",
        "컨셉", "콘셉", "시안", "네이밍", "브레인", "로고", "굿즈", "썸네일",
    )

    /** 첫 줄이 안 나와서 미루게 되는 일. */
    private val FIRST_LINE_WORDS = listOf(
        "글", "원고", "에세이", "블로그", "메일", "편지", "일기", "소설",
        "후기", "리뷰", "대본", "스크립트", "기사", "자소서",
    )

    /**
     * 무슨 말을 어떤 순서로 할지가 반인 일.
     *
     * [FIRST_LINE_WORDS]와 겹쳐 보이지만 하는 일이 다르다. 저쪽은 시작 장벽을
     * 없애는 말이고 이쪽은 구조를 미리 잡는 말이다 — 발표 자료에 "첫문장만
     * 준비해둬"는 약하고, 일기에 "개요 잡아둬"는 과하다.
     */
    private val OUTLINE_WORDS = listOf(
        "보고서", "리포트", "발표", "제안", "논문", "계획서", "문서",
        "강의", "수업", "이력서", "정리해서", "회의록",
    )

    /**
     * 머리가 아니라 몸이 움직여야 하는 일.
     *
     * 이런 일은 생각이 막는 게 아니라 나가는 것이 막는다. 미리 해두라고 하면
     * 그냥 지금 하라는 말이 되니, 문턱인 준비 쪽만 한 칸 앞당긴다.
     */
    private val BODY_WORDS = listOf(
        "운동", "헬스", "러닝", "조깅", "요가", "필라테스", "산책", "수영",
        "등산", "스트레칭", "청소", "설거지", "빨래", "장보기", "마트",
        "외출", "이사", "정리정돈",
    )

    fun cardFor(context: Context): Card {
        val name = pickTaskName(context)
        if (name == null) {
            // 이름 부를 것이 없어도 남아 있는 일이 있으면 "이따 할 일"이다.
            // 아예 비어 있을 때만 정하자고 권한다.
            return if (hasAnyRemaining(context)) {
                Card(FALLBACK, BUTTON_DEFAULT)
            } else {
                Card(EMPTY_BODY, BUTTON_PLAN)
            }
        }
        return Card(bodyFor(name), BUTTON_DEFAULT)
    }

    private fun bodyFor(name: String): String {
        val shown = shorten(name)
        return when {
            CONCEPT_WORDS.any { name.contains(it) } ->
                "이따 할 '$shown' 10분간 콘셉트만 생각해둬도 훨씬 가벼워질 거라냥."
            OUTLINE_WORDS.any { name.contains(it) } ->
                "이따 할 '$shown' 10분간 개요만 대충 잡아둬도 훨씬 가벼워질 거라냥."
            FIRST_LINE_WORDS.any { name.contains(it) } ->
                "이따 할 '$shown' 10분간 첫문장만 준비해둬도 훨씬 가벼워질 거라냥."
            BODY_WORDS.any { name.contains(it) } ->
                "이따 할 '$shown' 10분간 뭐부터 준비할지만 정해둬도 훨씬 움직이기 좋을 거라냥."
            else ->
                "이따 할 '$shown' 10분만 미리 해두면 훨씬 가벼워질 거라냥."
        }
    }

    /** 머리로 하는 일인지. 10분을 앞당겨 얻는 것이 가장 큰 쪽이다. */
    private fun isMindWork(name: String): Boolean =
        CONCEPT_WORDS.any { name.contains(it) } ||
            OUTLINE_WORDS.any { name.contains(it) } ||
            FIRST_LINE_WORDS.any { name.contains(it) }

    /**
     * 이름을 불러줄 일 하나.
     *
     * 머리로 하는 일이 하나라도 있으면 그것부터 부른다. 10분을 앞당겨 가장
     * 크게 달라지는 쪽이라서다 — 콘셉트든 개요든 첫 줄이든, 미리 굴려둔 것이
     * 있으면 그 뒤가 통째로 수월해진다. 몸으로 하는 일은 그 10분이 준비 한
     * 칸을 앞당기는 정도다.
     *
     * 같은 갈래 안에서는 시각이 정해진 일이 먼저고(이따 있을 일이라는 게
     * 분명하다), 없으면 목록에서 먼저 나오는 것을 쓴다.
     */
    private fun pickTaskName(context: Context): String? {
        val names = candidates(context)
        if (names.isEmpty()) return null
        return names.firstOrNull { isMindWork(it) } ?: names.first()
    }

    /**
     * 이름을 부를 수 있는 일들. 부르고 싶은 순서대로.
     *
     * 아직 시작하지 않은 일만 본다 — 손을 댄 일에 "미리 해두라"고 할 수는 없다.
     * 약속(schedule)도 빼둔다. 시각에 가서 하는 것이라 10분을 앞당길 자리가 없다.
     */
    private fun candidates(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return emptyList()
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return emptyList()

        val now = Calendar.getInstance()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val timed = mutableListOf<Pair<Int, String>>()
        val untimed = mutableListOf<String>()

        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) continue
            if (item.optBoolean("inProgress", false)) continue
            if (item.optInt("elapsedSeconds", 0) > 0) continue
            if (item.optString("category", "") == "schedule") continue
            val text = item.optString("text", "").trim()
            if (text.isBlank()) continue

            val pieces = item.optString("timeStart", "").split(":")
            val minutes = if (pieces.size == 2) {
                val hour = pieces[0].toIntOrNull()
                val minute = pieces[1].toIntOrNull()
                if (hour == null || minute == null) null else hour * 60 + minute
            } else {
                null
            }

            if (minutes == null) {
                untimed += text
                continue
            }
            // 이미 지난 시각은 "이따"가 아니다.
            if (minutes <= nowMinutes) continue
            timed += minutes to text
        }

        timed.sortBy { it.first }
        return timed.map { it.second } + untimed
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
     */
    fun isDayFinished(context: Context): Boolean {
        val (remaining, done) = countTasks(context)
        return remaining == 0 && done > 0
    }

    /** 남은 개수와 끝낸 개수. */
    private fun countTasks(context: Context): Pair<Int, Int> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tasksRaw = prefs.getString(KEY_TASKS, null) ?: return 0 to 0
        val tasks = runCatching { JSONArray(tasksRaw) }.getOrNull() ?: return 0 to 0
        var remaining = 0
        var done = 0
        for (i in 0 until tasks.length()) {
            val item = tasks.optJSONObject(i) ?: continue
            if (item.optBoolean("done", false)) done++ else remaining++
        }
        return remaining to done
    }

    private fun shorten(text: String): String =
        if (text.length <= NAME_LIMIT) text else text.take(NAME_LIMIT) + "…"
}
