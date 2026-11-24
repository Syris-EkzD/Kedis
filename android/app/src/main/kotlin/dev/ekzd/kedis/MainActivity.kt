package dev.ekzd.kedis

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var knowledge: KnowledgeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        knowledge = KnowledgeChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        KedisWidgetProvider.refreshWidgets(this)
                        result.success(null)
                    }
                    "syncThemeMode" -> {
                        KedisWidgetThemePreferences.setThemeMode(this, call.arguments as? String)
                        KedisWidgetProvider.refreshWidgets(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android document picker uses an activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (knowledge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        knowledge?.close()
        knowledge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        // Retained as the existing Flutter/native protocol identifier.
        const val WIDGET_CHANNEL = "dewwit/widget"
    }
}
