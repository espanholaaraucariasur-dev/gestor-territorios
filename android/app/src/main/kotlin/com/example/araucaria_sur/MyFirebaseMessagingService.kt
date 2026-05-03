package com.example.araucaria_sur

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MyFirebaseMessagingService : FlutterActivity() {
    private val CHANNEL = "com.example.araucaria_sur/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getNotificationToken") {
                // Handle token retrieval if needed
                result.success("Token handled in Dart")
            } else {
                result.notImplemented()
            }
        }
    }
}
