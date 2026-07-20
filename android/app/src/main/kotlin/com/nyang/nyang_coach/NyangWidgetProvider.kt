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

                val remainingCount = NyangWidgetMood.readInt(widgetData, "remaining_count")

                setImageViewResource(R.id.mini_cat_image, NyangWidgetMood.catImageRes(widgetData))

                if (hasTimedSchedule) {
                    // 시계+시간 / 일정명 2줄 좌측 정렬 (iOS 미니 위젯과 동일)
                    setViewVisibility(R.id.mini_schedule_block, View.VISIBLE)
                    setViewVisibility(R.id.mini_info_text, View.GONE)
                    setTextViewText(R.id.mini_schedule_time, scheduleTime)
                    setTextViewText(R.id.mini_schedule_title, scheduleTitle)
                } else {
                    setViewVisibility(R.id.mini_schedule_block, View.GONE)
                    setViewVisibility(R.id.mini_info_text, View.VISIBLE)
                    // 글자 크기는 레이아웃의 자동 축소(autoSize, 최대 18sp)가 담당한다.
                    if (NyangWidgetMood.isAwayOverDay(widgetData)) {
                        setTextViewText(R.id.mini_info_text, "집사 보고싶다옹...")
                    } else {
                        setTextViewText(
                            R.id.mini_info_text,
                            WidgetTextFormatter.formatMiniRemainingCount(remainingCount, "#8B7CFF")
                        )
                    }
                }
                WidgetResponsiveStyle.applyMini(
                    context,
                    appWidgetManager,
                    widgetId,
                    this,
                    hasTwoLineText = hasTimedSchedule
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
}
