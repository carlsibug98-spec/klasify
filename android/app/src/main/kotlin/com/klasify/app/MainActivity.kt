package com.klasify.app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

private const val NEXT_CLASS_WIDGET_CHANNEL = "klasify/next_class_widget"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NEXT_CLASS_WIDGET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "updateSchedule") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val scheduleJson = call.argument<String>("scheduleJson")
            if (scheduleJson == null) {
                result.error(
                    "invalid_schedule",
                    "The widget schedule payload is missing.",
                    null,
                )
                return@setMethodCallHandler
            }

            try {
                getSharedPreferences(
                    NextClassWidgetProvider.PREFERENCES_NAME,
                    MODE_PRIVATE,
                ).edit()
                    .putString(NextClassWidgetProvider.SCHEDULE_KEY, scheduleJson)
                    .apply()
                NextClassWidgetProvider.updateAllWidgets(this)
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "widget_update_failed",
                    error.message ?: "Could not update the Next Class widget.",
                    null,
                )
            }
        }
    }
}
