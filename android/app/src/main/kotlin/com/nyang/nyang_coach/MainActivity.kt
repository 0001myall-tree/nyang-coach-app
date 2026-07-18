package com.coscene.nyangcoach

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val morningAlarmChannel = "nyang_coach/morning_alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, morningAlarmChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleMorningAlarm" -> {
                        val triggerMillis = call.argument<Long>("triggerMillis")
                        val payload = call.argument<String>("payload")
                        if (triggerMillis == null || payload.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing triggerMillis or payload", null)
                            return@setMethodCallHandler
                        }
                        MorningAlarmScheduler.cancel(this)
                        MorningAlarmScheduler.schedule(this, triggerMillis, payload)
                        result.success(null)
                    }
                    "cancelMorningAlarm" -> {
                        MorningAlarmScheduler.cancel(this)
                        result.success(null)
                    }
                    "startMorningVibration" -> {
                        startMorningVibration()
                        result.success(null)
                    }
                    "stopMorningVibration" -> {
                        stopMorningVibration()
                        result.success(null)
                    }
                    "canPostNotifications" -> {
                        result.success(canPostNotifications())
                    }
                    "canScheduleExactAlarms" -> {
                        result.success(canScheduleExactAlarms())
                    }
                    "canUseFullScreenIntent" -> {
                        result.success(canUseFullScreenIntent())
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        prepareAlarmWindow()
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val morningPayload = intent.getStringExtra(MorningAlarmScheduler.EXTRA_PAYLOAD)
        if (morningPayload != null && morningPayload.startsWith("morning:")) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("flutter.native_morning_payload", morningPayload)
                .putLong("flutter.native_morning_alarm_at", System.currentTimeMillis())
                .commit()
        }

        val isWidgetIntent = intent.data?.let {
            it.scheme == "nyangcoach" && it.host == "widget"
        } ?: false
        val route = intent.getStringExtra("route")
        val coachId = if (isWidgetIntent) "cat" else intent.getStringExtra("coach_id")
        
        android.util.Log.d("WidgetIntent", "handleIntent called with route: $route, coachId: $coachId")
        if (route != null || coachId != null) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            if (route != null) {
                editor.putString("flutter.widget_route", route)
            }
            if (coachId != null) {
                editor.putString("flutter.widget_coach_id", coachId)
            }
            editor.commit()
        }
    }

    private fun prepareAlarmWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        return notificationManager.canUseFullScreenIntent()
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun startMorningVibration() {
        val pattern = longArrayOf(0, 450, 180, 450, 350, 900, 900)
        val effect = VibrationEffect.createWaveform(pattern, 0)
        getVibrator().vibrate(effect)
    }

    private fun stopMorningVibration() {
        getVibrator().cancel()
    }

    private fun getVibrator(): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }
}
