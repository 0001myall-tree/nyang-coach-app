package com.coscene.nyangcoach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NyangWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.nyang_widget_layout).apply {
                val scheduleTime = widgetData.getString("widget_schedule_time", "")?.trim().orEmpty()
                val scheduleTitle = widgetData.getString("widget_schedule_title", "")?.trim().orEmpty()
                val hasTimedSchedule = scheduleTime.isNotEmpty() && scheduleTitle.isNotEmpty()
                val usesCompactSchedule = hasTimedSchedule && scheduleTitle.length <= 6
                val characterKind = widgetData.getString("character_widget_kind", "cheer")?.trim().orEmpty()
                val characterStatus = widgetData.getString("character_widget_status", "")?.trim().orEmpty()
                val characterTitle = widgetData.getString("character_widget_title", "")?.trim().orEmpty()
                val hasCoreTask = !hasTimedSchedule &&
                    characterKind == "core" &&
                    characterStatus.isNotEmpty() &&
                    characterTitle.isNotEmpty()
                val hasInProgressTask = !hasTimedSchedule &&
                    !hasCoreTask &&
                    characterKind == "in_progress" &&
                    characterStatus.isNotEmpty() &&
                    characterTitle.isNotEmpty()
                val usesCompactInProgress = hasInProgressTask && characterStatus.length <= 3
                val usesCompactLayout = usesCompactSchedule || usesCompactInProgress

                val pawCount = NyangWidgetMood.readInt(widgetData, "character_widget_paws").coerceIn(0, 5)

                setImageViewResource(R.id.mini_cat_image, NyangWidgetMood.catImageRes(widgetData))
                setImageViewResource(R.id.mini_cat_image_compact, NyangWidgetMood.catImageRes(widgetData))
                setViewVisibility(R.id.mini_cat_image_compact, if (usesCompactLayout) View.VISIBLE else View.GONE)
                setViewVisibility(R.id.mini_cat_image, if (usesCompactLayout) View.GONE else View.VISIBLE)

                if (hasTimedSchedule) {
                    // 짧은 일정은 한 줄로 압축해 휑한 느낌을 줄이고,
                    // 긴 일정은 기존 2줄 구조로 읽기 좋게 유지한다.
                    setViewVisibility(R.id.mini_schedule_block, if (usesCompactSchedule) View.GONE else View.VISIBLE)
                    setViewVisibility(R.id.mini_schedule_compact_block, if (usesCompactSchedule) View.VISIBLE else View.GONE)
                    setViewVisibility(R.id.mini_info_text, View.GONE)
                    setViewVisibility(R.id.mini_paw_row, View.GONE)
                    setImageViewResource(R.id.mini_schedule_status_icon, R.drawable.ic_fa_clock)
                    setImageViewResource(R.id.mini_schedule_compact_icon, R.drawable.ic_fa_clock)
                    setTextViewText(R.id.mini_schedule_time, scheduleTime)
                    setTextViewText(R.id.mini_schedule_title, scheduleTitle)
                    setTextViewText(R.id.mini_schedule_compact_text, "$scheduleTime $scheduleTitle")
                } else if (hasCoreTask) {
                    setViewVisibility(R.id.mini_schedule_block, View.VISIBLE)
                    setViewVisibility(R.id.mini_schedule_compact_block, View.GONE)
                    setViewVisibility(R.id.mini_info_text, View.GONE)
                    setViewVisibility(R.id.mini_paw_row, View.GONE)
                    setImageViewResource(R.id.mini_schedule_status_icon, R.drawable.ic_fa_star_widget)
                    setTextViewText(R.id.mini_schedule_time, characterStatus)
                    setTextViewText(R.id.mini_schedule_title, characterTitle)
                } else if (hasInProgressTask) {
                    setViewVisibility(R.id.mini_schedule_block, if (usesCompactInProgress) View.GONE else View.VISIBLE)
                    setViewVisibility(R.id.mini_schedule_compact_block, if (usesCompactInProgress) View.VISIBLE else View.GONE)
                    setViewVisibility(R.id.mini_info_text, View.GONE)
                    setViewVisibility(R.id.mini_paw_row, View.GONE)
                    setImageViewResource(R.id.mini_schedule_status_icon, R.drawable.ic_fa_rotate_widget)
                    setImageViewResource(R.id.mini_schedule_compact_icon, R.drawable.ic_fa_rotate_widget)
                    setTextViewText(R.id.mini_schedule_time, characterStatus)
                    setTextViewText(R.id.mini_schedule_title, characterTitle)
                    setTextViewText(R.id.mini_schedule_compact_text, "$characterStatus $characterTitle")
                } else {
                    setViewVisibility(R.id.mini_schedule_block, View.GONE)
                    setViewVisibility(R.id.mini_schedule_compact_block, View.GONE)
                    setViewVisibility(R.id.mini_info_text, View.GONE)
                    setViewVisibility(R.id.mini_paw_row, View.VISIBLE)
                    setMiniPawProgress(this, pawCount)
                }
                WidgetResponsiveStyle.applyMini(
                    context,
                    appWidgetManager,
                    widgetId,
                    this,
                    hasTwoLineText = (hasTimedSchedule && !usesCompactSchedule) || hasCoreTask || (hasInProgressTask && !usesCompactInProgress),
                    hasCompactTimedSchedule = usesCompactLayout
                )

                val intentRemaining = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_TASKS"
                    data = Uri.parse("nyangcoach://widget/cat/tasks")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks")
                    putExtra("coach_id", "cat")
                }
                val pendingRemaining = PendingIntent.getActivity(context, 1003, intentRemaining, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.widget_root, pendingRemaining)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun setMiniPawProgress(views: RemoteViews, pawCount: Int) {
        val pawIds = intArrayOf(
            R.id.mini_paw_1,
            R.id.mini_paw_2,
            R.id.mini_paw_3,
            R.id.mini_paw_4,
            R.id.mini_paw_5
        )
        pawIds.forEachIndexed { index, viewId ->
            views.setImageViewResource(
                viewId,
                if (index < pawCount) R.drawable.ic_widget_paw_filled else R.drawable.ic_widget_paw_outline
            )
        }
    }
}
