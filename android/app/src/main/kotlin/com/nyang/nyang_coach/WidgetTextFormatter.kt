package com.coscene.nyangcoach

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

    fun formatMiniScheduleMessage(time: String, title: String, pointColor: String): SpannableString {
        val normalizedTime = time.trim()
        val gap = "  "
        val text = "${normalizedTime}${gap}${title.trim().replace(Regex("\\s+"), " ")}"
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(Color.parseColor(pointColor)),
                0,
                normalizedTime.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                ForegroundColorSpan(Color.parseColor("#262429")),
                normalizedTime.length + gap.length,
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

    fun formatCharacterRemainingCount(count: Int, pointColor: String): SpannableString {
        val countText = count.toString()
        val text = "오늘 할 일 ${countText}개 남음"
        val countStart = text.indexOf(countText)
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(Color.parseColor(pointColor)),
                countStart,
                countStart + countText.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    fun formatMiniRemainingCount(count: Int, pointColor: String): SpannableString {
        val countText = count.toString()
        val text = "남은 일정 ${countText}개"
        val countStart = text.indexOf(countText)
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(Color.parseColor(pointColor)),
                countStart,
                countStart + countText.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    fun formatCharacterEmptyPrompt(): String {
        return "집사야 오늘 뭐할까?"
    }
}
