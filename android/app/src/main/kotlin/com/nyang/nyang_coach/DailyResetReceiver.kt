package com.coscene.nyangcoach

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 자정 5분 뒤에 깨어나 하루 목록 정리를 Dart에게 넘긴다.
 *
 * 앱이 떠 있으면(뒤에 숨어 있어도) 그 앱에게 맡긴다. 꺼져 있으면 화면 없는
 * 앱을 잠깐 띄워 정리만 하고 닫는다. 둘을 동시에 돌리지 않는 이유는, 목록을
 * 고치는 쪽이 둘이면 나중에 저장한 쪽이 앞의 정리를 덮기 때문이다.
 *
 * 소리도 화면도 없다.
 */
class DailyResetReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL = "nyang_coach/daily_reset"

        /** 이만큼 지나도 안 끝나면 접는다. 방송을 오래 붙들면 시스템이 앱을 죽인다. */
        private const val TIMEOUT_MILLIS = 50_000L

        /** 떠 있는 앱의 통로. MainActivity가 엔진을 만들 때 채우고 치울 때 비운다. */
        @Volatile
        var appChannel: MethodChannel? = null

        private var headless: FlutterEngine? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DailyResetScheduler.ACTION_RUN) return
        val app = context.applicationContext
        // 다음 날 것을 먼저 건다. 정리가 도중에 실패해도 내일은 온다.
        DailyResetScheduler.rearmIfWanted(app)

        val pending = goAsync()
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        val finish = {
            if (!finished) {
                finished = true
                handler.removeCallbacksAndMessages(null)
                pending.finish()
            }
        }

        val channel = appChannel
        if (channel != null) {
            channel.invokeMethod(
                "run",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) = finish()
                    override fun error(code: String, message: String?, details: Any?) = finish()
                    override fun notImplemented() = finish()
                },
            )
            handler.postDelayed({ finish() }, TIMEOUT_MILLIS)
            return
        }

        if (headless != null) {
            // 앞의 것이 아직 도는 중이다.
            finish()
            return
        }
        runHeadless(app, handler) { finish() }
    }

    private fun runHeadless(context: Context, handler: Handler, onDone: () -> Unit) {
        val engine = try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)
            FlutterEngine(context).also { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .setMethodCallHandler { call, result ->
                        result.success(null)
                        if (call.method == "done") closeHeadless(onDone)
                    }
                // 정리 뒤 적극 코칭 예약이 이 통로로 알람을 건다. 화면에만 쓰는
                // 나머지는 이 앱에선 부를 일이 없다.
                MethodChannel(engine.dartExecutor.binaryMessenger, "nyang_coach/ongoing_nudge")
                    .setMethodCallHandler { call, result ->
                        if (!ActiveCoachingChannel.handle(context, call, result) &&
                            !OngoingStopChannel.handle(context, call, result)
                        ) {
                            result.notImplemented()
                        }
                    }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "backgroundDailyResetMain",
                    ),
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("DailyReset", "화면 없는 앱을 못 띄웠다", e)
            onDone()
            return
        }
        headless = engine
        handler.postDelayed({ closeHeadless(onDone) }, TIMEOUT_MILLIS)
    }

    private fun closeHeadless(onDone: () -> Unit) {
        headless?.destroy()
        headless = null
        onDone()
    }
}

/**
 * 진행 중 냥냥이를 내리는 통로. 자정 정리가 어제 켜둔 일을 멈추면, 그 일을
 * 붙잡고 있던 냥냥이도 같이 내려야 한다. 화면 없는 앱에서도 받는다.
 * 다루는 부름이면 true.
 */
object OngoingStopChannel {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "stop" -> stopRunning(context)
            // "다음 일"·"멈춘 일 다시 시작할까" 카드가 기다리는 중이면 남긴다.
            "stopUnlessNextTask" ->
                if (!OngoingNudgeState.isIdleNudge(context)) stopRunning(context)
            "clearStart" -> {
                OngoingNudgeState.clearStart(context)
                OngoingNudgeScheduler.cancelStart(context)
            }
            else -> return false
        }
        result.success(null)
        return true
    }

    private fun stopRunning(context: Context) {
        OngoingNudgeState.clear(context)
        OngoingNudgeScheduler.cancel(context)
        context.stopService(Intent(context, OngoingNudgeService::class.java))
    }
}

/**
 * 적극 코칭 알람을 거는 통로. 화면 있는 앱과 화면 없는 앱이 같이 쓴다.
 * 다루는 부름이면 true.
 */
object ActiveCoachingChannel {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "syncActiveCoaching" -> {
                // 계획은 Flutter가 이미 저장해뒀다. 여기서는 그 시각에
                // 깨어나도록 알람만 건다. 자리는 늘 하나라, 새로 걸면
                // 앞엣것은 덮인다.
                val atMillis = call.argument<Number>("atMillis")?.toLong()
                if (atMillis == null) {
                    OngoingNudgeScheduler.cancelActive(context)
                } else {
                    OngoingNudgeScheduler.scheduleActiveAt(context, atMillis)
                }
            }
            "clearActiveCoaching" -> OngoingNudgeScheduler.cancelActive(context)
            "armDailyReset" -> DailyResetScheduler.arm(context)
            "cancelDailyReset" -> DailyResetScheduler.cancel(context)
            else -> return false
        }
        result.success(null)
        return true
    }
}
