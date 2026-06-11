package com.nyang.nyang_coach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SecMaleWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sec_male_widget_layout).apply {
                val rawProgress = widgetData.all["progress"]
                val progress = (rawProgress as? Number)?.toInt() ?: (rawProgress as? String)?.toIntOrNull() ?: 0
                
                val coachMessage = widgetData.getString("coach_message_sec_male", "오늘도 함께 해보시죠.") ?: "오늘도 함께 해보시죠."
                
                val rawRemaining = widgetData.all["remaining_count"]
                val remainingCount = (rawRemaining as? Number)?.toInt() ?: (rawRemaining as? String)?.toIntOrNull() ?: 0

                setProgressBar(R.id.progress_bar, 100, progress, false)
                setTextViewText(R.id.coach_message, WidgetTextFormatter.formatCoachMessage(coachMessage))
                setTextViewText(R.id.remaining_count_text, WidgetTextFormatter.formatRemainingCount(remainingCount, "#2C365E"))
                WidgetResponsiveStyle.apply(context, appWidgetManager, widgetId, this)

                val intentRemaining = Intent(context, MainActivity::class.java).apply {
                    action = "sec_male_coach.OPEN_REMAINING_LIST"
                    data = Uri.parse("nyangcoach://widget/sec_male/tasks_remaining_bottom_sheet")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks_remaining_bottom_sheet")
                    putExtra("coach_id", "sec_male")
                }
                val pendingRemaining = PendingIntent.getActivity(context, 2003, intentRemaining, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.remaining_row, pendingRemaining)

                val intentChat = Intent(context, MainActivity::class.java).apply {
                    action = "sec_male_coach.OPEN_CHAT"
                    data = Uri.parse("nyangcoach://widget/sec_male/chat")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "chat")
                    putExtra("coach_id", "sec_male")
                }
                val pendingChat = PendingIntent.getActivity(context, 2001, intentChat, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.btn_open_chat, pendingChat)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
