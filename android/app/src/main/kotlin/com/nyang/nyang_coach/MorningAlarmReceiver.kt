package com.coscene.nyangcoach

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build

class MorningAlarmReceiver : BroadcastReceiver() {
    companion object {
        /**
         * 이 알림에는 목소리가 붙어 있어서, 뜨는 순간 시스템이 소리를 낸다.
         *
         * 앱이 전체화면을 열고 같은 목소리를 반복 재생하기 시작하면 둘이 겹쳐
         * 이중으로 들린다. 그래서 앱이 이어받는 자리에서 이 알림을 지운다
         * ([MainActivity]의 startMorningAlarmSound).
         */
        const val NOTIFICATION_ID = 7304

        /** 첫 알람에서 이만큼 지나면 뒤따르는 알람도, 앱을 열 때의 모닝콜도 없다. */
        const val FOLLOW_UP_WINDOW_MILLIS = 30 * 60_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == MorningAlarmScheduler.ACTION_FIRE) {
            val payload = intent.getStringExtra(MorningAlarmScheduler.EXTRA_PAYLOAD) ?: return
            fireMorningAlarm(context, payload)
            return
        }

        if (intent.action == MorningAlarmScheduler.ACTION_FOLLOW_UP) {
            val payload = intent.getStringExtra(MorningAlarmScheduler.EXTRA_PAYLOAD) ?: return
            fireMorningAlarm(context, payload, isFollowUp = true)
            return
        }

        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            MorningAlarmScheduler.rescheduleFromPrefs(context)
            return
        }
    }

    private fun fireMorningAlarm(context: Context, payload: String, isFollowUp: Boolean = false) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // 뒤따르는 알람은 아무도 첫 알람을 못 봤을 때만 부른다.
        //
        // 앱이 모닝콜 화면을 열면 "울릴 차례" 쪽지를 가져가면서 지운다. 쪽지가
        // 없다는 것은 이미 화면이 떴고 목소리가 돌고 있다는 뜻이라, 그 위에
        // 알림 소리를 더 얹을 이유가 없다.
        if (isFollowUp && prefs.getString("flutter.native_morning_payload", null) == null) {
            return
        }

        // 폰이 잠들어 있으면 뒤따르는 알람이 한참 밀렸다가 화면을 켤 때 터진다.
        // 첫 알람에서 너무 지났으면 그날 모닝콜은 끝난 것으로 보고 쪽지까지 치운다.
        val now = System.currentTimeMillis()
        val firstAt = prefs.getLong("flutter.native_morning_first_at", 0L)
        if (isFollowUp && firstAt > 0L && now - firstAt > FOLLOW_UP_WINDOW_MILLIS) {
            prefs.edit()
                .remove("flutter.native_morning_payload")
                .remove("flutter.native_morning_alarm_at")
                .remove("flutter.native_morning_first_at")
                .commit()
            return
        }

        val editor = prefs.edit()
            .putString("flutter.native_morning_payload", payload)
            .putLong("flutter.native_morning_alarm_at", now)
        // 첫 알람 시각은 뒤따르는 것들이 덮어쓰지 않는다. 덮으면 늦게 터진
        // 알람이 매번 "방금 울린 모닝콜"이 되어 위의 창을 빠져나간다.
        if (!isFollowUp) editor.putLong("flutter.native_morning_first_at", now)
        editor.commit()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            // 알림을 못 띄우더라도 내일 알람은 반드시 다시 걸어둔다.
            // 여기서 그냥 돌아가면 알람 체인이 끊겨, 앱을 열기 전까지 영영 울리지 않는다.
            if (!isFollowUp) MorningAlarmScheduler.rescheduleFromPrefs(context)
            return
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = MorningAlarmScheduler.ACTION_FIRE
            putExtra(MorningAlarmScheduler.EXTRA_PAYLOAD, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            7303,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val soundName = payload.split(":").getOrNull(2)?.takeIf { it.isNotBlank() }
        val rawSoundId = soundName?.let {
            context.resources.getIdentifier(it, "raw", context.packageName)
        } ?: 0
        val notificationSound = if (rawSoundId != 0) {
            Uri.parse("android.resource://${context.packageName}/raw/$soundName")
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        }
        val channelSuffix = soundName ?: "default"
        val channelId = "nyang_native_morning_alarm_${channelSuffix}_v6"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "냥냥코치 모닝콜",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "냥냥코치 모닝콜 알람입니다."
                setSound(
                    notificationSound,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 450, 180, 450, 350, 900)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setSound(notificationSound)
        }
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⏰ 모닝콜 시간입니다!")
            .setContentText("코치가 깨우러 왔어요. 얼른 일어나세요!")
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent)
            .setFullScreenIntent(openPendingIntent, true)
            .build()

        manager.notify(NOTIFICATION_ID, notification)
        if (!isFollowUp) {
            // 뒤따르는 것들은 여기서 건다. 예약 때 미리 걸어두면 바로 아래
            // 내일 예약이 그것들까지 데려가 버린다.
            MorningAlarmScheduler.scheduleFollowUps(context, payload)
            MorningAlarmScheduler.rescheduleFromPrefs(context)
        }
    }
}
