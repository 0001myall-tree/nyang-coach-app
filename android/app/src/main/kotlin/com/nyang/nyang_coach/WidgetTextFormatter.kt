package com.nyang.nyang_coach

import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan

object WidgetTextFormatter {
    fun formatCoachMessage(message: String): String {
        return message.trim().replace(Regex("\\s+"), " ")
    }

    fun formatScheduleMessage(time: String, title: String, pointColor: String): SpannableString {
        val normalizedTime = time.trim()
        val text = "${normalizedTime} ${title.trim().replace(Regex("\\s+"), " ")}"
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(Color.parseColor(pointColor)),
                0,
                normalizedTime.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                ForegroundColorSpan(Color.parseColor("#F5F1FF")),
                normalizedTime.length + 1,
                text.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    fun formatRemainingCount(count: Int, pointColor: String): SpannableString {
        val countText = count.toString()
        val text = "${countText}개 남음"
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(Color.parseColor(pointColor)),
                0,
                countText.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }
}
