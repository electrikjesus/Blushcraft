package com.blushcraft.blushcraft

import android.content.Context
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.blushcraft.blushcraft/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCamera" -> {
                    // Camera2 list only — never touch CameraX (crashes on 0-camera BlissOS).
                    try {
                        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        result.success(cm.cameraIdList.isNotEmpty())
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
