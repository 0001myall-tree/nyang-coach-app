package com.coscene.nyangcoach

import android.Manifest
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
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
    private val widgetStatusChannel = "nyang_coach/widget_status"
    private val ongoingNudgeChannel = "nyang_coach/ongoing_nudge"
    private var morningAlarmPlayer: MediaPlayer? = null

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
                    "startMorningAlarmSound" -> {
                        val soundName = call.argument<String>("soundName")
                        startMorningAlarmSound(soundName)
                        result.success(null)
                    }
                    "stopMorningAlarmSound" -> {
                        stopMorningAlarmSound()
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetStatusChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasInstalledCatHomeWidget" -> {
                        result.success(hasInstalledCatHomeWidget())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ongoingNudgeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "openOverlaySettings" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    "diagnose" -> {
                        // 조용히 실패하면 어디가 막힌 건지 알 길이 없다.
                        result.success(
                            mapOf(
                                "enabled" to OngoingNudgeState.isEnabled(this),
                                "overlay" to Settings.canDrawOverlays(this),
                                "notifications" to canPostNotifications(),
                                "exactAlarms" to canScheduleExactAlarms(),
                                "batteryRestricted" to isBatterySleepRestricted(),
                            ),
                        )
                    }
                    "isBatterySleepRestricted" -> {
                        result.success(isBatterySleepRestricted())
                    }
                    "openBatterySettings" -> {
                        openBatterySettings()
                        result.success(null)
                    }
                    "start" -> {
                        val taskId = call.argument<String>("taskId")
                        val taskText = call.argument<String>("taskText").orEmpty()
                        if (taskId.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing taskId", null)
                            return@setMethodCallHandler
                        }
                        // 같은 일정이 이미 걸려 있으면 예약을 처음부터 다시 걸지 않는다.
                        // 시작을 기다리던 일정이 이제 도는 중이면 다시 걸어야 한다 —
                        // 그때 잡아둔 예약은 시작할 시각을 보는 것이라 쓸모가 없다.
                        val alreadyRunning = OngoingNudgeState.taskId(this) == taskId &&
                            !OngoingNudgeState.isStartReminder(this)
                        OngoingNudgeState.start(this, taskId, taskText)
                        if (!alreadyRunning) {
                            OngoingNudgeScheduler.cancel(this)
                            OngoingNudgeScheduler.scheduleIn(
                                this,
                                OngoingNudgeScheduler.FIRST_DELAY_MILLIS,
                                OngoingNudgeScheduler.STAGE_FIRST,
                            )
                        }
                        result.success(null)
                    }
                    "remindStart" -> {
                        val taskId = call.argument<String>("taskId")
                        val taskText = call.argument<String>("taskText").orEmpty()
                        val startAtMillis = call.argument<Long>("startAtMillis")
                        if (taskId.isNullOrBlank() || startAtMillis == null) {
                            result.error("INVALID_ARGS", "Missing taskId or startAtMillis", null)
                            return@setMethodCallHandler
                        }
                        // 같은 일정을 이미 기다리고 있으면 예약을 다시 걸지 않는다.
                        // 저장은 자주 일어나고, 그때마다 다시 걸면 시각이 조금씩 밀린다.
                        val alreadyWaiting = OngoingNudgeState.taskId(this) == taskId &&
                            OngoingNudgeState.isStartReminder(this)
                        OngoingNudgeState.start(
                            this,
                            taskId,
                            taskText,
                            OngoingNudgeState.KIND_START,
                        )
                        OngoingNudgeState.setStartUntil(
                            this,
                            startAtMillis + OngoingNudgeScheduler.START_WINDOW_MILLIS,
                        )
                        if (!alreadyWaiting) {
                            OngoingNudgeScheduler.cancel(this)
                            OngoingNudgeScheduler.scheduleAt(
                                this,
                                startAtMillis,
                                OngoingNudgeScheduler.STAGE_FIRST,
                            )
                        }
                        result.success(null)
                    }
                    "remindNextTask" -> {
                        val taskId = call.argument<String>("taskId")
                        val taskText = call.argument<String>("taskText").orEmpty()
                        val fireAtMillis = call.argument<Long>("fireAtMillis")
                        if (taskId.isNullOrBlank() || fireAtMillis == null) {
                            result.error("INVALID_ARGS", "Missing taskId or fireAtMillis", null)
                            return@setMethodCallHandler
                        }
                        // 이 자리를 이미 도는 일정이나 시작을 기다리는 일정이 쓰고
                        // 있으면 넘겨받지 않는다. 하나를 끝냈다고 다른 일정의 알림이
                        // 깨지면 안 된다. "멈춘 일 다시 시작할까" 카드와는 서로
                        // 자유롭게 자리를 넘겨받는다 — 둘 다 급한 일이 아니다.
                        val slotTaken = OngoingNudgeState.isActive(this) &&
                            !OngoingNudgeState.isIdleNudge(this)
                        if (slotTaken) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val alreadyWaiting = OngoingNudgeState.taskId(this) == taskId &&
                            OngoingNudgeState.isNextTaskReminder(this)
                        OngoingNudgeState.start(
                            this,
                            taskId,
                            taskText,
                            OngoingNudgeState.KIND_NEXT,
                        )
                        if (!alreadyWaiting) {
                            OngoingNudgeScheduler.cancel(this)
                            OngoingNudgeScheduler.scheduleAt(
                                this,
                                fireAtMillis,
                                OngoingNudgeScheduler.STAGE_FIRST,
                            )
                        }
                        result.success(null)
                    }
                    "remindResume" -> {
                        val taskId = call.argument<String>("taskId")
                        val taskText = call.argument<String>("taskText").orEmpty()
                        val fireAtMillis = call.argument<Long>("fireAtMillis")
                        if (taskId.isNullOrBlank() || fireAtMillis == null) {
                            result.error("INVALID_ARGS", "Missing taskId or fireAtMillis", null)
                            return@setMethodCallHandler
                        }
                        val slotTaken = OngoingNudgeState.isActive(this) &&
                            !OngoingNudgeState.isIdleNudge(this)
                        if (slotTaken) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val alreadyWaiting = OngoingNudgeState.taskId(this) == taskId &&
                            OngoingNudgeState.isResumeReminder(this)
                        OngoingNudgeState.start(
                            this,
                            taskId,
                            taskText,
                            OngoingNudgeState.KIND_RESUME,
                        )
                        if (!alreadyWaiting) {
                            OngoingNudgeScheduler.cancel(this)
                            OngoingNudgeScheduler.scheduleAt(
                                this,
                                fireAtMillis,
                                OngoingNudgeScheduler.STAGE_FIRST,
                            )
                        }
                        result.success(null)
                    }
                    "setAppForeground" -> {
                        OngoingNudgeState.setAppForeground(
                            this,
                            call.argument<Boolean>("value") ?: false,
                        )
                        result.success(null)
                    }
                    "showTestNudge" -> {
                        // 30분을 기다리지 않고 지금 확인해보는 길.
                        // 앱을 나가야 나오므로 잠깐 여유를 두고 예약한다.
                        if (!OngoingNudgeState.isActive(this)) {
                            OngoingNudgeState.start(this, "nudge_test", "테스트")
                        }
                        OngoingNudgeScheduler.cancel(this)
                        OngoingNudgeState.openTestWindow(
                            this,
                            OngoingNudgeScheduler.TEST_WINDOW_MILLIS,
                        )
                        OngoingNudgeScheduler.scheduleIn(
                            this,
                            OngoingNudgeScheduler.TEST_DELAY_MILLIS,
                            OngoingNudgeScheduler.STAGE_TEST,
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        OngoingNudgeState.clear(this)
                        OngoingNudgeScheduler.cancel(this)
                        stopService(Intent(this, OngoingNudgeService::class.java))
                        result.success(null)
                    }
                    "stopUnlessNextTask" -> {
                        // 도는 일도, 시작 기다리는 일도 없을 때 부르는 자리다. 그런데
                        // "다음 일"이나 "멈춘 일 다시 시작할까" 카드가 22시까지 기다리는
                        // 중이라면, 지금 아무것도 없다는 이유만으로 그것까지 지우면
                        // 안 된다. 다른 저장이 일어날 때마다(할 일 편집 등) 이 자리가
                        // 불려서, 그러지 않으면 그 카드는 예약된 시각까지 살아남지 못한다.
                        if (!OngoingNudgeState.isIdleNudge(this)) {
                            OngoingNudgeState.clear(this)
                            OngoingNudgeScheduler.cancel(this)
                            stopService(Intent(this, OngoingNudgeService::class.java))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openOverlaySettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
    }

    /**
     * 기기가 앱을 재워버릴 수 있는 상태인가.
     *
     * 삼성의 "사용하지 않는 앱 절전"처럼, 앱이 걸어둔 예약을 기기가 미루거나
     * 묻어버리는 설정이다. 이 상태면 냥냥이가 제때 못 나가거나 아예 못 나간다.
     */
    private fun isBatterySleepRestricted(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return !power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * 배터리 최적화 목록을 연다.
     *
     * 한 번에 끄는 시스템 팝업도 있지만 그건 별도 권한이 필요하고 심사에서
     * 까다롭게 본다. 목록을 열어주고 사용자가 직접 고르게 한다.
     */
    private fun openBatterySettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // 이 화면이 없는 기기라면 앱 정보 화면으로 보낸다.
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    private fun hasInstalledCatHomeWidget(): Boolean {
        val appWidgetManager = AppWidgetManager.getInstance(this)
        val miniWidgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(this, NyangWidgetProvider::class.java)
        )
        val characterWidgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(this, CatCharacterWidgetProvider::class.java)
        )
        return miniWidgetIds.isNotEmpty() || characterWidgetIds.isNotEmpty()
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

    private fun startMorningAlarmSound(soundName: String?) {
        stopMorningAlarmSound()
        val alarmUri = resolveAlarmSoundUri(soundName) ?: return
        val player = MediaPlayer()
        try {
            player.apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                setDataSource(applicationContext, alarmUri)
                isLooping = true
                setVolume(1.0f, 1.0f)
                setOnErrorListener { player, _, _ ->
                    player.release()
                    if (morningAlarmPlayer === player) morningAlarmPlayer = null
                    true
                }
                prepare()
                start()
            }
            morningAlarmPlayer = player
        } catch (e: Exception) {
            player.release()
            morningAlarmPlayer = null
        }
    }

    private fun stopMorningAlarmSound() {
        morningAlarmPlayer?.let {
            try {
                if (it.isPlaying) it.stop()
            } catch (_: IllegalStateException) {
            } finally {
                it.release()
            }
        }
        morningAlarmPlayer = null
    }

    private fun resolveAlarmSoundUri(soundName: String?): Uri? {
        val rawSoundId = soundName
            ?.takeIf { it.isNotBlank() }
            ?.let { resources.getIdentifier(it, "raw", packageName) }
            ?: 0
        if (rawSoundId != 0) {
            return Uri.parse("android.resource://$packageName/$rawSoundId")
        }
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
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
