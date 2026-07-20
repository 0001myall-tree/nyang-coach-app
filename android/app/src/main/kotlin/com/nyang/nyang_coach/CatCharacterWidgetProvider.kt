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

class CatCharacterWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cat_character_widget_layout).apply {
                val scheduleTime = widgetData.getString("widget_schedule_time", "")?.trim().orEmpty()
                val scheduleTitle = widgetData.getString("widget_schedule_title", "")?.trim().orEmpty()
                val hasTimedSchedule = scheduleTime.isNotEmpty() && scheduleTitle.isNotEmpty()

                val remainingCount = NyangWidgetMood.readInt(widgetData, "remaining_count")
                val progress = NyangWidgetMood.readInt(widgetData, "progress").coerceIn(0, 100)
                val hasNoTodayItems = remainingCount == 0 && progress == 0

                // 시간 일정 없이 24시간 이상 미접속이면 "집사, 보고싶다옹...."을
                // 띄우고 일정 보기 버튼을 숨긴다. (iOS 가로 위젯과 동일)
                val showsMissYouMessage = !hasTimedSchedule && NyangWidgetMood.isAwayOverDay(widgetData)

                if (hasTimedSchedule) {
                    setViewVisibility(R.id.cat_character_time_row, View.VISIBLE)
                    setTextViewText(R.id.cat_character_time, scheduleTime)
                    setTextViewText(R.id.cat_character_text, scheduleTitle)
                } else {
                    setViewVisibility(R.id.cat_character_time_row, View.GONE)
                    setTextViewText(
                        R.id.cat_character_text,
                        when {
                            showsMissYouMessage -> "집사,\n보고싶다옹...."
                            hasNoTodayItems -> WidgetTextFormatter.formatCharacterEmptyPrompt()
                            else -> WidgetTextFormatter.formatCharacterRemainingCount(remainingCount, "#8B7CFF")
                        }
                    )
                }
                setViewVisibility(
                    R.id.cat_character_button,
                    if (showsMissYouMessage) View.GONE else View.VISIBLE
                )
                setImageViewResource(R.id.cat_character_image, NyangWidgetMood.catImageRes(widgetData))

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_CHARACTER_WIDGET"
                    data = Uri.parse("nyangcoach://widget/cat/tasks")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks")
                    putExtra("coach_id", "cat")
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    4003,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.cat_character_widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
