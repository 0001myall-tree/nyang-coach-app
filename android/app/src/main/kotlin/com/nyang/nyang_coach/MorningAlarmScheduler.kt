package com.coscene.nyangcoach

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

object MorningAlarmScheduler {
    private const val REQUEST_CODE = 7301
    private const val SHOW_REQUEST_CODE = 7302
    const val ACTION_FIRE = "com.coscene.nyangcoach.MORNING_ALARM_FIRE"
    const val ACTION_SHOW = "com.coscene.nyangcoach.MORNING_ALARM_SHOW"
    const val EXTRA_PAYLOAD = "payload"

    fun schedule(context: Context, triggerMillis: Long, payload: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("flutter.native_morning_trigger_millis", triggerMillis)
            .putString("flutter.native_morning_scheduled_payload", payload)
            .commit()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fireIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_PAYLOAD, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val firePendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_CODE,
            fireIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val showIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SHOW
            putExtra(EXTRA_PAYLOAD, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            SHOW_REQUEST_CODE,
            showIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(triggerMillis, showPendingIntent),
            firePendingIntent,
        )
    }

    fun rescheduleFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.nyang_morning_call_enabled", false)
        if (!enabled) {
            cancel(context)
            return
        }
        val payload = prefs.getString("flutter.native_morning_scheduled_payload", null) ?: return
        val time = prefs.getString("flutter.nyang_morning_call_time", null) ?: return
        val parts = time.split(":")
        if (parts.isEmpty()) return
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: return
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: 0

        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DATE, 1)
            }
        }
        schedule(context, next.timeInMillis, payload)
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fireIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_FIRE
        }
        val firePendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_CODE,
            fireIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (firePendingIntent != null) {
            alarmManager.cancel(firePendingIntent)
            firePendingIntent.cancel()
        }

        val showIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_SHOW
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            SHOW_REQUEST_CODE,
            showIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        showPendingIntent?.cancel()

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .remove("flutter.native_morning_trigger_millis")
            .remove("flutter.native_morning_scheduled_payload")
            .commit()
    }
}
