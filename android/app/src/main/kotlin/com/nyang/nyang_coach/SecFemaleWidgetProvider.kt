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

class SecFemaleWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sec_female_widget_layout).apply {
                val rawMasterAccess = widgetData.all["master_widget_access"]
                val hasMasterAccess = (rawMasterAccess as? Boolean)
                    ?: rawMasterAccess?.toString()?.toBooleanStrictOrNull()
                    ?: false
                val rawProgress = widgetData.all["progress"]
                val progress = if (hasMasterAccess) {
                    (rawProgress as? Number)?.toInt() ?: (rawProgress as? String)?.toIntOrNull() ?: 0
                } else {
                    0
                }
                
                val coachMessage = if (hasMasterAccess) {
                    widgetData.getString("coach_message_sec_female", "오늘 하루도 응원합니다.") ?: "오늘 하루도 응원합니다."
                } else {
                    "마스터 플랜 전용 위젯이에요."
                }
                val scheduleTime = widgetData.getString("widget_schedule_time", "")?.trim().orEmpty()
                val scheduleTitle = widgetData.getString("widget_schedule_title", "")?.trim().orEmpty()
                val hasTimedSchedule = hasMasterAccess && scheduleTime.isNotEmpty() && scheduleTitle.isNotEmpty()
                
                val rawRemaining = widgetData.all["remaining_count"]
                val remainingCount = if (hasMasterAccess) {
                    (rawRemaining as? Number)?.toInt() ?: (rawRemaining as? String)?.toIntOrNull() ?: 0
                } else {
                    0
                }

                setProgressBar(R.id.progress_bar, 100, progress, false)
                setTextViewText(
                    R.id.coach_message,
                    if (hasTimedSchedule) {
                        WidgetTextFormatter.formatScheduleMessage(scheduleTime, scheduleTitle, "#C4A8E6")
                    } else {
                        WidgetTextFormatter.formatCoachMessage(coachMessage)
                    }
                )
                setViewVisibility(R.id.message_icon, if (hasTimedSchedule) View.GONE else View.VISIBLE)
                setTextViewText(R.id.remaining_count_text, WidgetTextFormatter.formatRemainingCount(remainingCount, "#C4A8E6"))
                WidgetResponsiveStyle.apply(context, appWidgetManager, widgetId, this)

                val intentRemaining = Intent(context, MainActivity::class.java).apply {
                    action = "sec_female_coach.OPEN_TASKS"
                    data = Uri.parse("nyangcoach://widget/cat/tasks")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "tasks")
                    putExtra("coach_id", "cat")
                }
                val pendingRemaining = PendingIntent.getActivity(context, 3003, intentRemaining, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.remaining_row, pendingRemaining)

                val intentChat = Intent(context, MainActivity::class.java).apply {
                    action = "sec_female_coach.OPEN_CHAT"
                    data = Uri.parse("nyangcoach://widget/cat/chat")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "chat")
                    putExtra("coach_id", "cat")
                }
                val pendingChat = PendingIntent.getActivity(context, 3001, intentChat, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                setOnClickPendingIntent(R.id.btn_open_chat, pendingChat)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
