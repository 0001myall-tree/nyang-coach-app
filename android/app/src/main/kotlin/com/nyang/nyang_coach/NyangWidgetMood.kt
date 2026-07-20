package com.coscene.nyangcoach

import android.content.SharedPreferences

/// iOS 위젯(NyangWidget.swift)과 동일한 냥냥이 표정/멘트 정책.
/// 우선순위: 휴식 모드 > 미접속(48h/24h) > 목표 달성률(10/51/90%).
object NyangWidgetMood {

    fun readInt(widgetData: SharedPreferences, key: String): Int {
        val raw = widgetData.all[key]
        return (raw as? Number)?.toInt() ?: (raw as? String)?.toIntOrNull() ?: 0
    }

    private fun readLong(widgetData: SharedPreferences, key: String): Long {
        val raw = widgetData.all[key]
        return (raw as? Number)?.toLong() ?: (raw as? String)?.toLongOrNull() ?: 0L
    }

    private fun readBool(widgetData: SharedPreferences, key: String): Boolean {
        val raw = widgetData.all[key]
        return (raw as? Boolean) ?: (raw as? String)?.toBooleanStrictOrNull() ?: false
    }

    fun isVacation(widgetData: SharedPreferences): Boolean =
        readBool(widgetData, "vacation_mode")

    private fun hoursSinceLastOpened(widgetData: SharedPreferences): Double? {
        val lastOpenedMillis = readLong(widgetData, "last_opened_at")
        if (lastOpenedMillis <= 0L) return null
        return (System.currentTimeMillis() - lastOpenedMillis) / 3_600_000.0
    }

    /// 휴식 모드가 아닌 상태로 24시간 이상 앱을 열지 않았는지 여부.
    /// 이때는 남은 일정 개수가 의미 없으므로 "집사 보고싶다옹..." 문구를 쓴다.
    fun isAwayOverDay(widgetData: SharedPreferences): Boolean {
        if (isVacation(widgetData)) return false
        val hours = hoursSinceLastOpened(widgetData) ?: return false
        return hours >= 24
    }

    fun catImageRes(widgetData: SharedPreferences): Int {
        if (isVacation(widgetData)) return R.drawable.iphonecatwidget7
        hoursSinceLastOpened(widgetData)?.let { hours ->
            if (hours >= 48) return R.drawable.iphonecatwidget6
            if (hours >= 24) return R.drawable.iphonecatwidget5
        }
        val progress = readInt(widgetData, "progress").coerceIn(0, 100)
        return when {
            progress >= 90 -> R.drawable.iphonecatwidget4
            progress >= 51 -> R.drawable.iphonecatwidget3
            progress >= 10 -> R.drawable.iphonecatwidget2
            else -> R.drawable.iphonecatwidget1
        }
    }
}
