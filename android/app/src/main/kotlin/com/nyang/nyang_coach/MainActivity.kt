package com.nyang.nyang_coach

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val route = intent.getStringExtra("route")
        val coachId = intent.getStringExtra("coach_id")
        
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
}
