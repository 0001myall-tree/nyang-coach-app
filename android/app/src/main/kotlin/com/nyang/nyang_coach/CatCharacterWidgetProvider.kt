package com.nyang.nyang_coach

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

                val rawRemaining = widgetData.all["remaining_count"]
                val remainingCount = (rawRemaining as? Number)?.toInt() ?: (rawRemaining as? String)?.toIntOrNull() ?: 0
                val rawProgress = widgetData.all["progress"]
                val progress = (rawProgress as? Number)?.toInt() ?: (rawProgress as? String)?.toIntOrNull() ?: 0
                val hasNoTodayItems = remainingCount == 0 && progress.coerceIn(0, 100) == 0

                if (hasTimedSchedule) {
                    setViewVisibility(R.id.cat_character_time, View.VISIBLE)
                    setTextViewText(R.id.cat_character_time, scheduleTime)
                    setTextViewText(R.id.cat_character_text, scheduleTitle)
                } else {
                    setViewVisibility(R.id.cat_character_time, View.GONE)
                    setTextViewText(
                        R.id.cat_character_text,
                        if (hasNoTodayItems) {
                            WidgetTextFormatter.formatCharacterEmptyPrompt()
                        } else {
                            WidgetTextFormatter.formatCharacterRemainingCount(remainingCount, "#8B7CFF")
                        }
                    )
                }
                setImageViewResource(
                    R.id.cat_character_image,
                    when (progress.coerceIn(0, 100)) {
                        0 -> R.drawable.cat_widget1
                        100 -> R.drawable.cat_widget3
                        else -> R.drawable.cat_widget2
                    }
                )

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = "nyang_coach.OPEN_CHARACTER_WIDGET"
                    data = Uri.parse("nyangcoach://widget/cat/tasks_remaining_bottom_sheet")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks_remaining_bottom_sheet")
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
